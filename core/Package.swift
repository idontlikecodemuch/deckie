// swift-tools-version: 6.0
// DeckieAudio: the in-memory audio type (`AudioBuffer`) shared by the decoder and the analysers; no Foundation.
// DeckieCore: Deckie's own ideas (beat grid fit, Camelot, pair scoring, loudness, key, structure), written
// once in plain Swift with no Apple-only framework, so the Apple apps and the Windows and Linux builder share them.
// DeckieLab: reads the lab's feature files (mixer/features/<id>.json, mixer/candidates.json) into DeckieCore types,
// for the parity tests and, later, the Mac benchmark; it also turns them into crate records.
// DeckieCrate: the crate file (docs/architecture/crate-format.md): its model, a canonical writer and a checking reader.
// crate-from-lab: a command-line tool that writes a crate from the lab's feature files (core/Tools/make_crate_fixture.sh).
// DeckieDecode: audio files to float samples for the analysers: WAV and AIFF in plain Swift; MP3 through dr_mp3
// (CDrMp3) and FLAC through dr_flac (CDrFlac), vendored public-domain C files (DEPENDENCIES.md); AAC is recognised
// and reported as not supported yet, a copy-protected MP4 as protected. It re-exports DeckieAudio.
// CDrMp3, CDrFlac: dr_mp3.h and dr_flac.h compiled as plain C, the same on Linux, Windows and macOS; nothing is
// downloaded at build time.
// COnnxRuntime: ONNX Runtime's C API header (vendored, MIT; DEPENDENCIES.md) and a small C shim that opens the
// library at run time (dlopen, or LoadLibraryExW on Windows), so nothing links it and the package builds without it.
// DeckieInference: ONNX Runtime from Swift (`OnnxRuntime`, `OnnxSession`), the Beat This! beat tracker
// (`BeatTracker`) and the vocal tagger (`YAMNet`, `DeckieVocalTagger`) on it; the models' front ends, the tracker's
// chunking and peak picking, and the averaging of patches into bars are plain Swift in DeckieCore.
// DeckieEngine: the Windows and Linux analyser, mixer/analyze.py's pipeline in the lab's order on the ported pieces
// (decoder, Beat This! through ONNX Runtime, DeckieCore's DSP); its record serialises to the lab's feature JSON and
// converts to a crate track.
// DeckieTestSupport: synthesised test audio (drums, chords, the engine's test track) and the beat fixture, shared by the
// test targets (not a product).
import PackageDescription

let package = Package(
    name: "DeckieCore",
    products: [
        .library(name: "DeckieCore", targets: ["DeckieCore"]),
        .library(name: "DeckieLab", targets: ["DeckieLab"]),
        .library(name: "DeckieAudio", targets: ["DeckieAudio"]),
        .library(name: "DeckieDecode", targets: ["DeckieDecode"]),
        .library(name: "DeckieInference", targets: ["DeckieInference"]),
        .library(name: "DeckieCrate", targets: ["DeckieCrate"]),
        .library(name: "DeckieEngine", targets: ["DeckieEngine"]),
    ],
    targets: [
        .target(name: "DeckieAudio"),
        .target(name: "DeckieCore", dependencies: ["DeckieAudio"]),
        .target(name: "DeckieLab", dependencies: ["DeckieCore", "DeckieCrate"]),
        .target(name: "DeckieCrate", dependencies: ["DeckieCore"]),
        .executableTarget(name: "crate-from-lab", dependencies: ["DeckieLab", "DeckieCrate"]),
        .target(name: "CDrMp3"),
        .target(name: "CDrFlac"),
        .target(name: "DeckieDecode", dependencies: ["DeckieAudio", "CDrMp3", "CDrFlac"]),
        .target(name: "COnnxRuntime", linkerSettings: [.linkedLibrary("dl", .when(platforms: [.linux]))]),
        .target(name: "DeckieInference", dependencies: ["COnnxRuntime", "DeckieAudio", "DeckieCore"]),
        .target(name: "DeckieEngine",
                dependencies: ["DeckieDecode", "DeckieCore", "DeckieInference", "DeckieCrate", "DeckieAudio"]),
        .target(name: "DeckieTestSupport", dependencies: ["DeckieAudio", "DeckieCore"], path: "Tests/DeckieTestSupport"),
        .testTarget(name: "DeckieCoreTests", dependencies: ["DeckieCore", "DeckieLab", "DeckieAudio", "DeckieTestSupport"],
                    exclude: ["Fixtures"]),
        .testTarget(name: "DeckieDecodeTests", dependencies: ["DeckieDecode"], exclude: ["Fixtures"]),
        .testTarget(name: "DeckieInferenceTests", dependencies: ["DeckieInference", "DeckieCore", "DeckieAudio", "DeckieTestSupport"],
                    exclude: ["Fixtures"]),
        .testTarget(name: "DeckieCrateTests", dependencies: ["DeckieCrate", "DeckieLab", "DeckieCore"]),
        .testTarget(name: "DeckieEngineTests",
                    dependencies: ["DeckieEngine", "DeckieDecode", "DeckieCore", "DeckieInference", "DeckieCrate",
                                   "DeckieLab", "DeckieAudio", "DeckieTestSupport"]),
    ]
)
