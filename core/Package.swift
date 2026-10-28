// swift-tools-version: 6.0
// DeckieCore: Deckie's own ideas (beat grid fit, Camelot, pair scoring, later the crate format), written once in
// plain Swift with no Apple-only framework, so the Apple apps and the Windows and Linux builder share them.
// DeckieLab: reads the lab's feature files (mixer/features/<id>.json, mixer/candidates.json) into DeckieCore types,
// for the parity tests and, later, the Mac benchmark.
// DeckieDecode: audio files to float samples for the analysers, in plain Swift with no library: WAV today; MP3 and
// AAC are recognised and reported as not supported yet.
import PackageDescription

let package = Package(
    name: "DeckieCore",
    products: [
        .library(name: "DeckieCore", targets: ["DeckieCore"]),
        .library(name: "DeckieLab", targets: ["DeckieLab"]),
        .library(name: "DeckieDecode", targets: ["DeckieDecode"]),
    ],
    targets: [
        .target(name: "DeckieCore"),
        .target(name: "DeckieLab", dependencies: ["DeckieCore"]),
        .target(name: "DeckieDecode"),
        .testTarget(name: "DeckieCoreTests", dependencies: ["DeckieCore", "DeckieLab"], exclude: ["Fixtures"]),
        .testTarget(name: "DeckieDecodeTests", dependencies: ["DeckieDecode"], exclude: ["Fixtures"]),
    ]
)
