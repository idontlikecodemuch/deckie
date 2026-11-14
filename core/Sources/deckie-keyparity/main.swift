import Foundation
import DeckieCore

// The parity harness of the three-answer key reader (`ThreeAnswerKey`): reads clips from standard input and prints
// each one's answer, so that mixer/keytrial/kt_three.py (`parity`) can compare the Swift reader with its Python
// reference on the very same samples. No audio is decoded here and none is in the repository.
//
//   input, repeated:   an 8-byte little-endian count n, then n little-endian float32 samples (mono, 44.1 kHz);
//                      a negative count ends the run
//   output, per clip:  answer ("key", "home", "none"), the key ("A minor", or empty), the home note ("A", or empty),
//                      the tuning, row A's 24 scores, row B's 24 scores, tab-separated on one line

// With the arguments `--learned <path of deckie-key.f16>` it runs the learned reader (`LearnedKey`) instead, for
// `kt_x4.py parity`.
var learnedModel: LearnedKey.Model? = nil
if let i = CommandLine.arguments.firstIndex(of: "--learned"), i + 1 < CommandLine.arguments.count,
   let data = FileManager.default.contents(atPath: CommandLine.arguments[i + 1]) {
    learnedModel = try LearnedKey.Model(pinnedFile: data)
}
let note = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
let stdin = FileHandle.standardInput
let stdout = FileHandle.standardOutput

func readExactly(_ count: Int) -> Data? {
    var data = Data()
    while data.count < count {
        guard let chunk = try? stdin.read(upToCount: count - data.count), !chunk.isEmpty else { return nil }
        data.append(chunk)
    }
    return data
}

while let head = readExactly(8) {
    let n = head.withUnsafeBytes { Int(Int64(littleEndian: $0.loadUnaligned(as: Int64.self))) }
    if n < 0 { break }
    guard let body = readExactly(4 * n) else { break }
    let mono: [Float] = body.withUnsafeBytes { raw in
        (0..<n).map { Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: 4 * $0, as: UInt32.self))) }
    }
    if let learnedModel {
        // The learned reader: answer, the likeliest key (0 to 23, or -1), then its 24 probabilities.
        let l = try LearnedKey.read(mono, sampleRate: LearnedKey.sampleRate, model: learnedModel)
        let fields = [l.answer.name, "\(l.best ?? -1)"] + l.probabilities.map { String(format: "%.6f", $0) }
        stdout.write((fields.joined(separator: "\t") + "\n").data(using: .utf8)!)
        continue
    }
    let r = try ThreeAnswerKey.read(mono, sampleRate: HPCPKey.sampleRate)
    var fields: [String]
    switch r.answer {
    case .key(let pc, let minor): fields = ["key", "\(note[pc]) \(minor ? "minor" : "major")", note[pc]]
    case .home(let pc): fields = ["home", "", note[pc]]
    case .notSure: fields = ["none", "", ""]
    }
    fields.append(String(format: "%.6f", r.tuning))
    fields += (r.scoresA + r.scoresB).map { String(format: "%.9f", $0) }
    stdout.write((fields.joined(separator: "\t") + "\n").data(using: .utf8)!)
}
