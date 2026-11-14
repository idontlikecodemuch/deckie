import Foundation
import Testing
import DeckieCore
import DeckieCrate
import DeckieBuild
import DeckieRecognition
@testable import DeckieDesk

/// A fresh, empty folder for one test.
func scratch(_ name: String) throws -> URL {
    let u = FileManager.default.temporaryDirectory.appendingPathComponent("deckie-desk-tests-\(ProcessInfo.processInfo.processIdentifier)")
        .appendingPathComponent(name + "-" + UUID().uuidString.prefix(8))
    try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    return u
}

/// A small entry with a place.
func entry(_ id: String, _ title: String, disc: String?, folder: String?, track: Int?, rel: String?,
           others: [CrateTrack.Place] = []) -> CrateTrack {
    CrateTrack(id: id, file: .init(name: (rel ?? title) as String, rel: rel, bytes: 10, sha1Head: nil, durationS: 200),
               ident: .init(title: title, source: "tag", disc: disc, folder: folder, track: track, otherPlaces: others),
               analysis: .init(engine: "deckie-0.4.0", analysedAt: "2026-11-13T00:00:00Z", device: "Mac15,6", secs: 1, level: 1),
               engine: .init(family: "deckie", version: "0.4.0", platform: "macos-arm64", fidelity: 1, models: [],
                             decoder: .init(name: "avf", version: "1")))
}

func crate(_ tracks: [CrateTrack], name: String = "Night") -> Crate {
    Crate(manifest: CrateManifest(crateId: "c0ffee", name: name, createdAt: "2026-11-13T00:00:00Z", devicesSeen: ["Mac15,6"]),
          tracks: tracks)
}

@Suite struct DeskHomeTests {
    @Test func theOverrideDecidesWhereEverythingGoes() throws {
        let h = DeskHome.standard(environment: [DeskHome.environmentVariable: "/tmp/somewhere/Desk"])
        #expect(h.root.path == "/tmp/somewhere/Desk")
        #expect(h.cratesFolder.path == "/tmp/somewhere/Desk/Crates")
        #expect(h.store.records.path == "/tmp/somewhere/Desk/Files/records")
        let real = DeskHome.standard(environment: [:])
        #expect(real.root.lastPathComponent == "Deckie Desk")
        // the system's own folder for an app's data: "Application Support" on a Mac; Linux and Windows have their own
        #if os(macOS)
        #expect(real.root.path.contains("Application Support"))
        #endif
    }
}

@Suite struct CrateShelfTests {
    @Test func cratesAreMadeListedMostRecentFirstRenamedAndDeleted() throws {
        let home = DeskHome(root: try scratch("shelf"))
        let shelf = home.shelf
        let a = try shelf.make(name: "Friday night", now: 100)
        let b = try shelf.make(name: "Stick 3", now: 200)
        let c = try shelf.make(name: "friday night", now: 300)
        #expect(c.name == "friday night 2")
        #expect(shelf.list().map(\.id) == [c.id, b.id, a.id])
        try shelf.touch(a.id, now: 150)
        #expect(shelf.mostRecent?.id == a.id, "opening a crate makes it the most recent, whatever the clock says")
        let renamed = try shelf.rename(b.id, to: "  Friday night ")
        #expect(renamed.name == "Friday night 3", "names are told apart without regard to capitals")
        try shelf.delete(c.id)
        #expect(!FileManager.default.fileExists(atPath: shelf.folder(c.id).path))
        #expect(Set(shelf.list().map(\.name)) == ["Friday night", "Friday night 3"])
    }

    @Test func importIsACopyAndExportWritesOne() throws {
        let root = try scratch("import")
        let home = DeskHome(root: root.appendingPathComponent("home"))
        let original = root.appendingPathComponent("From a friend.deckiecrate")
        try CrateWriter.write(crate([entry("aaaaaaaaaaaaaaaa", "One", disc: nil, folder: nil, track: nil, rel: "One.wav")],
                                    name: "From a friend"), to: original)
        let manifest = original.appendingPathComponent("manifest.json")
        let bytes = try Data(contentsOf: manifest)
        let stamp = try FileManager.default.attributesOfItem(atPath: manifest.path)[.modificationDate] as? Date

        let first = try home.shelf.importCopy(of: original)
        let second = try home.shelf.importCopy(of: original)
        #expect(first.name == "From a friend" && second.name == "From a friend 2")
        #expect(try CrateReader.read(from: home.shelf.package(second.id)).manifest.name == "From a friend 2")
        #expect(try Data(contentsOf: manifest) == bytes, "the original is never changed")
        #expect(try FileManager.default.attributesOfItem(atPath: manifest.path)[.modificationDate] as? Date == stamp)

        let out = root.appendingPathComponent("out/Mine.deckiecrate")
        try home.shelf.exportCopy(first.id, to: out)
        #expect(try CrateReader.read(from: out).tracks.map(\.id) == ["aaaaaaaaaaaaaaaa"])
        let box = try home.shelf.outboxCopy(second.id)
        #expect(box.lastPathComponent == "From a friend 2.deckiecrate")
        let empty = try home.shelf.make(name: "Empty")
        #expect(throws: DeskError.self) { try home.shelf.exportCopy(empty.id, to: root.appendingPathComponent("x.deckiecrate")) }
    }
}

@Suite struct FileStoreTests {
    @Test func signaturesAndPrintsAreKeptByTheFilesId() throws {
        let store = FileStore(folder: try scratch("store"))
        #expect(store.signature("abc") == nil && store.print("abc") == nil)
        try store.saveSignature(Data([1, 2, 3]), made: .init(madeBy: "Mac15,6", madeAt: "2026-11-13T00:00:00Z"), id: "abc")
        #expect(store.signature("abc")?.data == Data([1, 2, 3]))
        #expect(store.signature("abc")?.made.madeBy == "Mac15,6")
        let p = RecordingPrint(words: [0, 1, 0xFFFF_FFFF, 12345], sounding: [true, false, true, true])
        try store.savePrint(p, id: "abc")
        #expect(store.print("abc") == p)
        #expect(FileStore.decodePrint(Data("DKP1".utf8)) == nil)
    }

    /// The fingerprint for recognition (D35) is kept with the file's analysis, by the file's id, and comes back as
    /// it went in; a file with no analysis yet keeps none.
    @Test func theFingerprintIsKeptWithTheFilesAnalysis() throws {
        let store = FileStore(folder: try scratch("store-fingerprint"))
        let id = "aaaaaaaaaaaaaaaa"
        let landmarks = Landmarks(frames: [0, 3, 3, 900, 901], pitches: [1, 0x4500, 0x8ABC, 0xC001, 13000], frameCount: 1000)
        let print = CrateTrack.Fingerprint(landmarks, madeBy: "Mac15,6", madeAt: "2026-11-14T00:00:00Z")
        #expect(store.fingerprint(id) == nil)
        #expect(try !store.saveFingerprint(print, id: id))
        // The analysis as the builder keeps it: the record, made before the fingerprint.
        try FileManager.default.createDirectory(at: store.records, withIntermediateDirectories: true)
        let track = try JSONSerialization.jsonObject(with: JSONEncoder().encode(entry(id, "Song", disc: nil, folder: nil, track: nil, rel: "Song.mp3")))
        try JSONSerialization.data(withJSONObject: ["engine": "deckie-test", "track": track])
            .write(to: store.records.appendingPathComponent("\(id).json"))
        #expect(store.hasRecord(id) && store.fingerprint(id) == nil)
        #expect(try store.saveFingerprint(print, id: id))
        #expect(store.fingerprint(id) == print && store.fingerprint(id)?.landmarks == landmarks)
        #expect(try Data(contentsOf: store.records.appendingPathComponent("\(id).dkl")) == landmarks.encoded())
        // It is not the print that finds copies, which is kept apart.
        #expect(store.print(id) == nil)
    }
}

@Suite struct NameCorrectionTests {
    @Test func aFixIsKeptWhenTheSongIsReadAgain() throws {
        let read = crate([entry("aaaaaaaaaaaaaaaa", "01 Track", disc: "Stick 3", folder: "House", track: 1, rel: "House/01 Track.mp3"),
                          entry("bbbbbbbbbbbbbbbb", "Other", disc: "Stick 3", folder: "House", track: 2, rel: "House/02 Other.mp3")])
        var fixed = read
        fixed.tracks[0].ident.title = "Track"
        fixed.tracks[0].ident.artist = "The Artist"
        var corrections = NameCorrections()
        corrections.note(from: read, to: fixed)
        #expect(corrections.byId.keys.sorted() == ["aaaaaaaaaaaaaaaa"])

        // Saved, loaded (another run), and put back on what a re-read wrote: the tags again.
        let url = try scratch("corrections").appendingPathComponent("corrections.json")
        try corrections.save(to: url)
        var again = read
        again.tracks[1].ident.title = "Other (new tag)"
        #expect(NameCorrections.load(from: url).apply(to: &again) == 1)
        #expect(again.tracks[0].ident.title == "Track" && again.tracks[0].ident.artist == "The Artist")
        #expect(again.tracks[0].ident.source == "user")
        #expect(again.tracks[1].ident.title == "Other (new tag)", "names not fixed follow the file's tags")

        // An artist cleared is a fix too.
        var cleared = again
        cleared.tracks[0].ident.artist = nil
        corrections.note(from: again, to: cleared)
        var third = read
        corrections.apply(to: &third)
        #expect(third.tracks[0].ident.artist == nil && third.tracks[0].ident.title == "Track")
    }
}

@Suite struct PlacePathTests {
    /// A song on two sources; the first is read again without it; its file is still found, through the second.
    @Test func aSongOnTwoSourcesIsFoundThroughTheSecondWhenTheFirstNoLongerHasIt() throws {
        let root = try scratch("places")
        let stickA = root.appendingPathComponent("A"), stickB = root.appendingPathComponent("B")
        let fm = FileManager.default
        try fm.createDirectory(at: stickA.appendingPathComponent("House"), withIntermediateDirectories: true)
        try fm.createDirectory(at: stickB.appendingPathComponent("Set 1"), withIntermediateDirectories: true)
        try Data([1]).write(to: stickA.appendingPathComponent("House/01 Song.mp3"))
        try Data([1]).write(to: stickB.appendingPathComponent("Set 1/07 Song.mp3"))
        let id = "aaaaaaaaaaaaaaaa"
        let onA = CrateTrack.Place(disc: "A", folder: "House", track: 1)
        let onB = CrateTrack.Place(disc: "B", folder: "Set 1", track: 7)

        var paths = PlacePaths()
        paths.record([id: [ReadPlace(place: onA, rel: "House/01 Song.mp3")]], source: "A")
        paths.record([id: [ReadPlace(place: onB, rel: "Set 1/07 Song.mp3")]], source: "B")
        var c = crate([entry(id, "Song", disc: "A", folder: "House", track: 1, rel: "House/01 Song.mp3", others: [onB])])
        let roots = ["A": stickA, "B": stickB]
        #expect(paths.locate(c.tracks[0], roots: roots, musicFolder: nil) == stickA.appendingPathComponent("House/01 Song.mp3"))

        // A is read again without the song: the builder promotes the place on B and its path is unknown in the crate
        // file; the desk fills it from what it remembered, and finds the file there.
        try fm.removeItem(at: stickA.appendingPathComponent("House/01 Song.mp3"))
        c.tracks[0].ident.otherPlaces = [onB]
        c.tracks[0].promoteOtherPlace()
        #expect(c.tracks[0].file.rel == nil && c.tracks[0].ident.disc == "B")
        paths.record([:], source: "A")
        #expect(paths.fillMissingPaths(&c) == 1)
        #expect(c.tracks[0].file.rel == "Set 1/07 Song.mp3")
        #expect(paths.locate(c.tracks[0], roots: roots, musicFolder: nil) == stickB.appendingPathComponent("Set 1/07 Song.mp3"))

        // With both places still listed but A unplugged, the first source present is used.
        var both = crate([entry(id, "Song", disc: "A", folder: "House", track: 1, rel: "House/01 Song.mp3", others: [onB])])
        var p2 = PlacePaths()
        p2.record([id: [ReadPlace(place: onA, rel: "House/01 Song.mp3"), ReadPlace(place: onB, rel: "Set 1/07 Song.mp3")]],
                  source: nil)
        #expect(p2.locate(both.tracks[0], roots: ["A": root.appendingPathComponent("unplugged"), "B": stickB],
                          musicFolder: nil) == stickB.appendingPathComponent("Set 1/07 Song.mp3"))
        // A source renamed in the crate keeps its paths.
        both.renameDisc("B", to: "Stick B")
        p2.renameSource("B", to: "Stick B")
        #expect(p2.rel(for: id, at: .init(disc: "Stick B", folder: "Set 1", track: 7)) == "Set 1/07 Song.mp3")
    }

    @Test func twoFoldersWithOneNameAreTwoSources() throws {
        let root = try scratch("naming")
        let one = root.appendingPathComponent("one/Music"), two = root.appendingPathComponent("two/Music")
        try FileManager.default.createDirectory(at: one, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: two, withIntermediateDirectories: true)
        #expect(SourceNaming.unique("Music", root: one, roots: [:]) == "Music")
        #expect(SourceNaming.unique("Music", root: one, roots: ["Music": one]) == "Music")
        #expect(SourceNaming.unique("Music", root: two, roots: ["Music": one]) == "Music 2")
        #expect(SourceNaming.unique("Music", root: two, roots: ["Music": one, "Music 2": two]) == "Music 2")
        // A stick now mounted under another path is the same stick.
        #expect(SourceNaming.unique("Stick", root: two, roots: ["Stick": root.appendingPathComponent("gone")]) == "Stick")
    }
}

@Suite struct RemoveSourceTests {
    @Test func removingASourceTakesItsSongsOutAndKeepsSongsThatAreElsewhere() {
        let onlyA = entry("aaaaaaaaaaaaaaaa", "Only A", disc: "A", folder: "", track: 1, rel: "01.mp3")
        let both = entry("bbbbbbbbbbbbbbbb", "Both", disc: "A", folder: "", track: 2, rel: "02.mp3",
                         others: [.init(disc: "B", folder: "X", track: 4)])
        let onlyB = entry("cccccccccccccccc", "Only B", disc: "B", folder: "X", track: 1, rel: "X/01.mp3")
        let mac = entry("dddddddddddddddd", "Mac", disc: nil, folder: nil, track: nil, rel: "Mac.mp3",
                        others: [.init(disc: "A", folder: "", track: 3)])
        var c = crate([onlyA, both, onlyB, mac])
        c.manifest.importLog = .init(builtBy: "Mac15,6", builtAt: "2026-11-13T00:00:00Z", filesSeen: 6, tracks: 4,
                                     entries: [.init(rel: "A/bad.mp3", ext: "mp3", reason: "decode_error", message: "x"),
                                               .init(rel: "B/bad.mp3", ext: "mp3", reason: "decode_error", message: "y")])
        #expect(c.entriesOnlyOn(source: "A") == ["aaaaaaaaaaaaaaaa"])
        let gone = c.removeSource("A")
        #expect(gone == ["aaaaaaaaaaaaaaaa"])
        #expect(c.tracks.map(\.id) == ["bbbbbbbbbbbbbbbb", "cccccccccccccccc", "dddddddddddddddd"])
        let b = c.tracks[0]
        #expect(b.ident.ownPlace == .init(disc: "B", folder: "X", track: 4) && b.ident.otherPlaces.isEmpty)
        #expect(c.tracks[2].ident.otherPlaces.isEmpty && c.tracks[2].ident.disc == nil)
        #expect(c.manifest.importLog?.entries.map(\.rel) == ["B/bad.mp3"])
        #expect(c.manifest.importLog?.tracks == 3)
        // The music folder is a place too.
        #expect(c.entriesOnlyOn(source: nil) == ["dddddddddddddddd"])
        c.removeSource(nil)
        #expect(c.tracks.count == 2)
    }
}
