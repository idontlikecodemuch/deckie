import Foundation
import Testing
import DeckieCrate

// Writing and reading give back the same crate, and the same crate always gives the same bytes.

@Suite struct RoundTripTests {
    @Test func inMemoryRoundTripIsExactAndStable() throws {
        let crate = sampleCrate()
        #expect(crate.problems().isEmpty, "\(crate.problems())")
        let files = try CrateWriter.encode(crate)
        #expect(Set(files.keys) == ["manifest.json", "crate.json", "bars/a1.bin", "bars/b2.bin", "style/a1.bin"])
        let back = try CrateReader.decode(withSignatureFiles(files, crate))
        #expect(back == crate)
        #expect(try CrateWriter.encode(back) == files)
    }

    @Test func theTextIsCanonical() throws {
        let files = try CrateWriter.encode(sampleCrate())
        let manifest = String(decoding: files["manifest.json"]!, as: UTF8.self)
        #expect(manifest == #"{"crate_id":"0f6c1e2a","created_at":"2026-10-28T12:00:00Z","devices_seen":["linux-x86_64"],"# +
            #""engines_used":["deckie-oss-0.1"],"min_reader":1,"name":"Sample","schema":1}"# + "\n")
        let lines = String(decoding: files["crate.json"]!, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.count == 5)  // {"tracks":[, one line per track, ]}, and the empty string after the last newline
        #expect(lines.first == #"{"tracks":["#)
        #expect(lines[1].hasPrefix(#"{"analysis":{"analysed_at":"2026-10-28T12:00:00Z","device":"linux-x86_64","#))
        #expect(lines[1].hasSuffix(#""vocal":{"confidence":0.75,"heavy":false,"mean":0.6213,"source":"apple-mu"}},"#))
        #expect(lines[1].contains(#""features_present":["bars.drum","bars.lufs","bars.vocal","ends","grid","key","key_changes","loudness","mix_windows","onset_pattern","phrase","sections","style","tempo_segments","vocal"]"#))
        #expect(lines[2].contains(#""key_changes""#) == false && lines[2].contains(#""changes":null"#))
        #expect(lines[2].contains(#""style":null"#) && lines[2].contains(#""signatures":{}"#))
        #expect(lines[3] == "]}")
    }

    @Test func barsSidecarLayout() throws {
        let crate = sampleCrate()
        let bin = [UInt8](try CrateWriter.encode(crate)["bars/b2.bin"]!)
        #expect(Array(bin[0..<4]) == Array("DKB1".utf8))
        #expect(Array(bin[4..<16]) == [40, 0, 0, 0, 3, 0, 0, 0, 0, 0, 0, 0])
        #expect(bin.count == 16 + 2 * 3 * 40)
        // Series in features_present order: drum, lufs, vocal. The first lufs value is -20.
        let firstLufs = UInt16(bin[16 + 80]) | UInt16(bin[16 + 81]) << 8
        #expect(Half.value(firstLufs) == -20)
    }

    @Test func onDiskRoundTripLeavesOtherFilesAlone() throws {
        let crate = sampleCrate()
        let dir = try temporaryFolder().appendingPathComponent("Sample.deckiecrate")
        defer { try? FileManager.default.removeItem(at: dir.deletingLastPathComponent()) }

        // A listed signature must be in the package before the crate can be written.
        #expect(throws: CrateError.self) { try CrateWriter.write(crate, to: dir) }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("signatures"), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: dir.appendingPathComponent("signatures/a1_o.shazamsignature"))
        try Data("{}".utf8).write(to: dir.appendingPathComponent("prefs.json"))

        try CrateWriter.write(crate, to: dir)
        let first = try snapshot(dir)
        #expect(try CrateReader.read(from: dir) == crate)
        try CrateWriter.write(try CrateReader.read(from: dir), to: dir)
        #expect(try snapshot(dir) == first)

        // Dropping a track removes its sidecar and nothing else.
        var smaller = crate
        smaller.tracks.removeAll { $0.id == "b2" }
        try CrateWriter.write(smaller, to: dir)
        let after = try snapshot(dir)
        #expect(after["bars/b2.bin"] == nil && after["bars/a1.bin"] == first["bars/a1.bin"])
        #expect(after["prefs.json"] == Data("{}".utf8) && after["signatures/a1_o.shazamsignature"] == Data([1, 2, 3]))
        #expect(try CrateReader.read(from: dir) == smaller)
    }

    @Test func aNewerCrateCanBeReadButNotRewritten() throws {
        var crate = sampleCrate()
        let files = withSignatureFiles(try CrateWriter.encode(crate), crate)
        var manifest = try JSONSerialization.jsonObject(with: files["manifest.json"]!) as! [String: Any]
        manifest["schema"] = 2
        manifest["something_new"] = ["a": 1]
        var newer = files
        newer["manifest.json"] = try JSONSerialization.data(withJSONObject: manifest)
        let read = try CrateReader.decode(newer)
        #expect(read.manifest.schema == 2)
        crate.manifest.schema = 2
        #expect(read == crate)
        let error = try #require(throws: CrateError.self) { try CrateWriter.encode(read) }
        #expect(error.problems.map(\.path) == ["schema"])
        #expect(error.description.contains("newer Deckie"))
    }

    /// Every file under `dir`, by its path inside it.
    private func snapshot(_ dir: URL) throws -> [String: Data] {
        var out: [String: Data] = [:]
        let base = dir.standardizedFileURL.path
        for case let url as URL in FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)! {
            var isFolder: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) && isFolder.boolValue { continue }
            let path = String(url.standardizedFileURL.path.dropFirst(base.count + 1))
            out[path] = try Data(contentsOf: url)
        }
        return out
    }
}
