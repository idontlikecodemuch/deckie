// swift-tools-version: 6.0
// DeckieCore: Deckie's own ideas (beat grid fit, Camelot, pair scoring, later the crate format), written once in
// plain Swift with no Apple-only framework, so the Apple apps and the Windows and Linux builder share them.
// DeckieLab: reads the lab's feature files (mixer/features/<id>.json, mixer/candidates.json) into DeckieCore types,
// for the parity tests and, later, the Mac benchmark.
import PackageDescription

let package = Package(
    name: "DeckieCore",
    products: [
        .library(name: "DeckieCore", targets: ["DeckieCore"]),
        .library(name: "DeckieLab", targets: ["DeckieLab"]),
    ],
    targets: [
        .target(name: "DeckieCore"),
        .target(name: "DeckieLab", dependencies: ["DeckieCore"]),
        .testTarget(name: "DeckieCoreTests", dependencies: ["DeckieCore", "DeckieLab"], exclude: ["Fixtures"]),
    ]
)
