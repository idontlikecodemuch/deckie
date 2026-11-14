import Foundation
import Testing
import DeckieCore
@testable import DeckieCrate

/// The `key_home` block (D36, Nov 14, 2026; crate-format.md, "The home note"), both directions: a crate without it is
/// written and read exactly as before; a crate with it is read by the previous reader's shape as a song with no key.
@Suite struct KeyHomeTests {
    /// The sample crate with its second track's key replaced by a home note.
    static func crateWithHome() -> Crate {
        var c = sampleCrate()
        c.tracks[1].key = nil
        c.tracks[1].keyHome = .init(source: "three-answer", pitchClass: 9)
        return c
    }

    @Test func theBlock() {
        let h = CrateTrack.KeyHome(source: "three-answer", pitchClass: 9)
        #expect(h.note == "A" && h.pitchClass == 9 && h.camelot == ["8A", "11B"])
        #expect(CrateTrack.KeyHome(source: "three-answer", pitchClass: 1).note == "C#")
        #expect((0..<12).allSatisfy { pc in
            let k = CrateTrack.KeyHome(source: "x", pitchClass: pc)
            return Camelot.tonic(k.camelot[0])! == (pc, false) && Camelot.tonic(k.camelot[1])! == (pc, true)
        })
    }

    /// Without the block nothing changes: no `key_home` anywhere in the file, the feature list as it was, and the file
    /// read and written again is the same bytes.
    @Test func aCrateWithoutItIsWrittenAsBefore() throws {
        let c = sampleCrate()
        let files = try CrateWriter.encode(c)
        let json = try #require(files[CrateFormat.tracksFile].flatMap { String(data: $0, encoding: .utf8) })
        #expect(!json.contains("key_home"))
        #expect(c.tracks.allSatisfy { !$0.featuresPresent.contains(CrateFormat.Feature.keyHome) })
        let back = try CrateReader.decode(withSignatureFiles(files, c))
        #expect(back == c && back.tracks.allSatisfy { $0.keyHome == nil })
        #expect(try CrateWriter.encode(back) == files)
    }

    /// With the block: it is written, listed, read back, and the crate has no problems.
    @Test func aCrateWithItRoundTrips() throws {
        let c = Self.crateWithHome()
        #expect(c.problems().isEmpty, "\(c.problems())")
        #expect(c.tracks[1].featuresPresent.contains("key_home") && !c.tracks[1].featuresPresent.contains("key")
                && !c.tracks[1].featuresPresent.contains("key_changes"))
        let files = try CrateWriter.encode(c)
        let back = try CrateReader.decode(withSignatureFiles(files, c))
        #expect(back == c && back.tracks[1].keyHome == c.tracks[1].keyHome && back.tracks[0].keyHome == nil)
        #expect(try CrateWriter.encode(back) == files)
        // The only difference from the same crate with no key at all is the block and its name in the list.
        var plain = c; plain.tracks[1].keyHome = nil
        let a = try JSONSerialization.jsonObject(with: files[CrateFormat.tracksFile]!) as! [String: Any]
        let b = try JSONSerialization.jsonObject(with: CrateWriter.encode(plain)[CrateFormat.tracksFile]!) as! [String: Any]
        var ta = (a["tracks"] as! [[String: Any]])[1]; let tb = (b["tracks"] as! [[String: Any]])[1]
        let block = try #require(ta.removeValue(forKey: "key_home") as? [String: Any])
        #expect(block["source"] as? String == "three-answer" && block["note"] as? String == "A"
                && block["pitch_class"] as? Int == 9 && block["camelot"] as? [String] == ["8A", "11B"] && block.count == 4)
        ta["features_present"] = (ta["features_present"] as! [String]).filter { $0 != "key_home" }
        #expect(NSDictionary(dictionary: ta).isEqual(to: tb))
    }

    /// The reader as it was before the block existed: its record had no `key_home` member, so the decoder passes over
    /// it, and its check of `features_present` looked only at the fourteen names it knew. This is that shape, frozen:
    /// a file with the block reads through it with no problem, as a song with no key.
    @Test func thePreviousReaderShapeStillReadsIt() throws {
        struct OldTrack: Decodable {
            var id: String
            var key: CrateTrack.Key?
            var grid: CrateTrack.Grid?
            var featuresPresent: [String]
            enum CodingKeys: String, CodingKey { case id, key, grid, featuresPresent = "features_present" }
        }
        struct OldFile: Decodable { var tracks: [OldTrack] }
        let oldBlocks = ["grid", "tempo_segments", "key", "key_changes", "phrase", "sections", "mix_windows", "ends",
                         "loudness", "vocal", "onset_pattern", "style", "vocal_structure", "hooks"]
        let files = try CrateWriter.encode(Self.crateWithHome())
        let old = try JSONDecoder().decode(OldFile.self, from: files[CrateFormat.tracksFile]!)
        let t = old.tracks[1]
        #expect(t.key == nil && t.grid != nil)
        // The previous check: every name it knows is listed exactly when the record has the block.
        let has: Set<String> = ["grid"]                       // of the names it knows, what this minimal shape decodes
        #expect(!t.featuresPresent.contains("key") && t.featuresPresent.contains("grid"))
        for f in oldBlocks where ["grid", "key"].contains(f) { #expect(t.featuresPresent.contains(f) == has.contains(f)) }
        // The name it does not know is in the list and is not one it checks.
        #expect(t.featuresPresent.contains("key_home") && !oldBlocks.contains("key_home"))
    }

    /// For the by-hand proof with the previous reader: with DECKIE_KEYHOME_OUT set to a folder, the crate with the
    /// block is written there as a package, to be checked by a reader built from an earlier commit
    /// (`swift run deckie-e2e check <folder>`).
    @Test func writesACrateForAnOlderReaderToCheck() throws {
        guard let out = ProcessInfo.processInfo.environment["DECKIE_KEYHOME_OUT"], !out.isEmpty else { return }
        let c = Self.crateWithHome()
        let dir = URL(fileURLWithPath: out)
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("signatures"), withIntermediateDirectories: true)
        for t in c.tracks { for v in t.signatures.keys { try Data([0]).write(to: dir.appendingPathComponent("signatures/\(t.id)_\(v).shazamsignature")) } }
        try CrateWriter.write(c, to: dir)
        #expect(try CrateReader.read(from: dir) == c)
    }

    @Test func theValidatorNamesWhatIsWrong() throws {
        // Beside a key: refused.
        var c = sampleCrate()
        c.tracks[1].keyHome = .init(source: "three-answer", pitchClass: 9)
        #expect(c.problems().map(\.description).contains { $0.contains("key_home") && $0.contains("only for a record with no key block") })
        // A pitch class out of range, codes that are not the two on the note, a note that is not its name.
        c = Self.crateWithHome()
        c.tracks[1].keyHome = .init(source: "three-answer", note: "A", pitchClass: 12, camelot: ["8A", "11B"])
        #expect(c.problems().map(\.description).contains { $0.contains("key_home.pitch_class") })
        c.tracks[1].keyHome = .init(source: "three-answer", note: "A", pitchClass: 9, camelot: ["11B", "8A"])
        #expect(c.problems().map(\.description).contains { $0.contains("key_home.camelot") })
        c.tracks[1].keyHome = .init(source: "three-answer", note: "Bb", pitchClass: 9, camelot: ["8A", "11B"])
        #expect(c.problems().map(\.description).contains { $0.contains("key_home.note") })
        // The list must name it when the record has it, and not when it has not.
        let files = try CrateWriter.encode(Self.crateWithHome())
        var obj = try JSONSerialization.jsonObject(with: files[CrateFormat.tracksFile]!) as! [String: Any]
        var tracks = obj["tracks"] as! [[String: Any]]
        tracks[1]["features_present"] = (tracks[1]["features_present"] as! [String]).filter { $0 != "key_home" }
        obj["tracks"] = tracks
        var edited = files
        edited[CrateFormat.tracksFile] = try JSONSerialization.data(withJSONObject: obj)
        #expect(throws: (any Error).self) { try CrateReader.decode(withSignatureFiles(edited, Self.crateWithHome())) }
        #expect((try? CrateReader.decode(withSignatureFiles(files, Self.crateWithHome()))) != nil)
    }

    /// Scoring reads the home note from the block, and only when there is no key.
    @Test func scoringTakesTheHomeNote() throws {
        let c = Self.crateWithHome()
        let withHome = try #require(c.tracks[1].scoringTrack())
        #expect(withHome.camelot == "" && withHome.homePitchClass == 9)
        let keyed = try #require(c.tracks[0].scoringTrack())
        #expect(keyed.camelot == "7A" && keyed.homePitchClass == nil)
    }
}
