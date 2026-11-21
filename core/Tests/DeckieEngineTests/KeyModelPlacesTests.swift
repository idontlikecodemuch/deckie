import Foundation
import Testing
import DeckieCore
import DeckieEngine

// Where the learned key reader's file is looked for, and what happens with a file that is not the pinned one or with
// none: a tiny stand-in file in each place (never the trained numbers, which are not in the repository).

@Suite struct KeyModelPlacesTests {
    private func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("deckie-key-places-\(UUID().uuidString.prefix(8))")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func standIn(at url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not the key model".utf8).write(to: url)
    }

    @Test func theFileIsFoundInEachPlaceInOrder() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let name = LearnedKey.Model.fileName
        let program = root.appendingPathComponent("app"), core = root.appendingPathComponent("core")
        let byVariable = root.appendingPathComponent("elsewhere").appendingPathComponent("any-name.f16")
        let beside = program.appendingPathComponent("models").appendingPathComponent(name)
        let checkout = core.appendingPathComponent(".models").appendingPathComponent(name)

        // The order: the environment variable alone; else models/ beside the program, then core/.models.
        let both = KeyModel.candidates(environment: [:], programFolder: program, coreFolder: core)
        #expect(both == [beside.path, checkout.path])
        #expect(KeyModel.candidates(environment: [:], programFolder: nil, coreFolder: core) == [checkout.path])
        let named = KeyModel.candidates(environment: [KeyModel.environmentVariable: byVariable.path], programFolder: program, coreFolder: core)
        #expect(named == [byVariable.path])
        #expect(KeyModel.candidates(environment: [KeyModel.environmentVariable: ""], programFolder: program, coreFolder: core) == both)

        // Nothing there: not found.
        #expect(KeyModel.locate(in: both) == nil && KeyModel.locate(in: named) == nil)
        // In the checkout only, beside the program as well, and named by the variable: each is found where it is.
        try standIn(at: checkout)
        #expect(KeyModel.locate(in: both) == checkout.path)
        try standIn(at: beside)
        #expect(KeyModel.locate(in: both) == beside.path)
        try standIn(at: byVariable)
        #expect(KeyModel.locate(in: named) == byVariable.path)
        // The file's name carries its version.
        #expect(LearnedKey.Model.fileName == LearnedKey.Model.pinnedName + ".f16")
    }

    @Test func aFileThatIsNotThePinnedOneIsNotUsedAndTheLogSaysSo() throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent(LearnedKey.Model.fileName)
        try standIn(at: file)
        // The wrong hash is refused, the analyser gets no learned reader, and the line says why.
        #expect(throws: KeyModel.LoadError.self) { try KeyModel.load(path: file.path) }
        #expect(KeyModel.usable(file.path) == nil)
        let wrong = KeyModel.readerLine(path: file.path)
        #expect(wrong.hasPrefix("key reader: untrained (") && wrong.contains("not the pinned file"))
        // No file: the untrained reader, said plainly.
        #expect(KeyModel.usable(nil) == nil && KeyModel.usable(root.appendingPathComponent("none.f16").path) == nil)
        let none = KeyModel.readerLine(path: nil)
        #expect(none.hasPrefix("key reader: untrained (") && none.contains(LearnedKey.Model.fileName))
        // This computer's own line agrees with what a default analyser will have.
        if let name = KeyModel.defaultName {
            #expect(KeyModel.readerLine.hasPrefix("key reader: learned, \(name), "))
            #expect(KeyModel.note == nil)
        } else {
            #expect(KeyModel.readerLine.hasPrefix("key reader: untrained ("))
            #expect(KeyModel.note != nil && KeyModel.loadDefault() == nil)
        }
    }
}
