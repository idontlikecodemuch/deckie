import Foundation
import Testing
import DeckieAudio
import DeckieCrate
import DeckieBuild
import DeckieTestSupport
@testable import DeckieDesk

/// Which source a stick is (Nov 25, 2026): two sticks that share a name ("USB") and are mounted one after the
/// other at the same path are two sources, and the same stick is one source wherever it is mounted. The system's
/// identity of a drive comes through one seam (`SourceIdentity.Reader`), so these run alike on every platform.
@Suite struct SourceIdentityTests {
    static let a = SourceIdentity(volume: "E9E3CF2A-9CF2-3725-A285-F4196FCEE104", inside: "")
    static let b = SourceIdentity(volume: "8DE71ADC-B546-375F-A5CC-9E57A64104F4", inside: "")
    static let onA = SourceIdentity.Found(identity: a, ownDisk: false)
    static let onB = SourceIdentity.Found(identity: b, ownDisk: false)
    static let none = SourceIdentity.Found(identity: nil, ownDisk: false)

    /// A made-up stick at `url`: a file of 10 bytes (the size `entry` gives a song) at each path.
    func stick(_ url: URL, _ rels: [String], bytes: Int = 10) throws {
        for r in rels {
            let f = url.appendingPathComponent(r)
            try FileManager.default.createDirectory(at: f.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 7, count: bytes).write(to: f)
        }
    }

    func files(_ rels: [String]) -> [SourceNaming.Recorded.File] { rels.map { .init(rel: $0, bytes: 10) } }

    static let songsOfA = ["Warm up/01 One.mp3", "Warm up/02 Two.mp3", "Peak/01 Three.mp3", "Peak/02 Four.mp3"]

    @Test func twoSticksWithOneNameAtOnePathAreTwoSources() throws {
        let root = try scratch("ids-two")
        let mount = root.appendingPathComponent("USB"), second = root.appendingPathComponent("USB 1")
        // Stick B is in now, where stick A was; it even holds copies of A's songs: its identity says it is another.
        try stick(mount, Self.songsOfA)
        let recordedA = SourceNaming.Recorded(name: "USB", root: mount, identity: Self.a, files: files(Self.songsOfA))
        #expect(SourceNaming.choose("USB", root: mount, found: Self.onB, recorded: [recordedA]) == "USB 2")
        // Both in: A at the path the system gives the second, B where A was. Each is its own source.
        let both = [SourceNaming.Recorded(name: "USB", root: second, identity: Self.a, files: files(Self.songsOfA)),
                    SourceNaming.Recorded(name: "USB 2", root: mount, identity: Self.b, files: [])]
        #expect(SourceNaming.choose("USB", root: mount, found: Self.onA, recorded: both) == "USB")
        #expect(SourceNaming.choose("USB", root: second, found: Self.onB, recorded: both) == "USB 2")
        // A third stick with the same name and no identity of its own, holding none of their songs, is a third.
        try FileManager.default.removeItem(at: mount)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        #expect(SourceNaming.choose("USB", root: mount, found: Self.none, recorded: both) == "USB 3")
    }

    @Test func theSameStickIsOneSourceWhereverItMounts() throws {
        let recorded = [SourceNaming.Recorded(name: "USB", root: URL(fileURLWithPath: "/Volumes/USB"),
                                              identity: Self.a, files: files(Self.songsOfA))]
        // Mounted under another path, with nothing there to look at: its identity is enough.
        #expect(SourceNaming.choose("USB", root: URL(fileURLWithPath: "/Volumes/USB 1"), found: Self.onA,
                                    recorded: recorded, size: { _ in nil }) == "USB")
        // Renamed by the DJ, it is still that source; its old name is free for another stick.
        let renamed = [SourceNaming.Recorded(name: "Friday", root: URL(fileURLWithPath: "/Volumes/USB"),
                                             identity: Self.a, files: [])]
        #expect(SourceNaming.choose("USB", root: URL(fileURLWithPath: "/Volumes/USB"), found: Self.onA,
                                    recorded: renamed) == "Friday")
        #expect(SourceNaming.choose("USB", root: URL(fileURLWithPath: "/Volumes/USB"), found: Self.onB,
                                    recorded: renamed) == "USB")
    }

    @Test func aFolderOnAStickIsToldApartByTheStickAndFoundWhereItMoved() throws {
        let root = try scratch("ids-folder")
        let music = root.appendingPathComponent("USB/Music"), moved = root.appendingPathComponent("USB/Sets/Music")
        let rels = ["01 One.mp3", "02 Two.mp3", "03 Three.mp3"]
        let recorded = [SourceNaming.Recorded(name: "Music", root: music,
                                              identity: SourceIdentity(volume: Self.a.volume, inside: "Music"), files: files(rels))]
        // Another stick's folder of the same name at the same path: another source.
        try stick(music, rels)
        #expect(SourceNaming.choose("Music", root: music, found: .init(identity: SourceIdentity(volume: Self.b.volume, inside: "Music"), ownDisk: false),
                                    recorded: recorded) == "Music 2")
        // The same stick, the folder moved on it: its songs are there, so it is the same source.
        try stick(moved, rels)
        let atMoved = SourceIdentity.Found(identity: SourceIdentity(volume: Self.a.volume, inside: "Sets/Music"), ownDisk: false)
        #expect(SourceNaming.choose("Music", root: moved, found: atMoved, recorded: recorded) == "Music")
        // Another folder of that name on the same stick, without its songs: another source.
        let other = root.appendingPathComponent("USB/Old/Music")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let atOther = SourceIdentity.Found(identity: SourceIdentity(volume: Self.a.volume, inside: "Old/Music"), ownDisk: false)
        #expect(SourceNaming.choose("Music", root: other, found: atOther, recorded: recorded) == "Music 2")
    }

    @Test func withNoIdentityTheSongsThemselvesDecideAndDoubtMakesANewSource() throws {
        let root = try scratch("ids-none")
        let mount = root.appendingPathComponent("USB")
        let recorded = [SourceNaming.Recorded(name: "USB", root: mount, identity: nil, files: files(Self.songsOfA))]
        // A stranger at the very path, holding none of its songs.
        try stick(mount, ["01 Other.mp3"])
        #expect(SourceNaming.choose("USB", root: mount, found: Self.none, recorded: recorded) == "USB 2")
        // Its own stick, at another path, holding its songs.
        let back = root.appendingPathComponent("USB 1")
        try stick(back, Self.songsOfA)
        #expect(SourceNaming.choose("USB", root: back, found: Self.none, recorded: recorded) == "USB")
        // The stick gives an identity now and gave none before: the songs decide, as above.
        #expect(SourceNaming.choose("USB", root: back, found: Self.onA, recorded: recorded) == "USB")
        // Recorded with an identity, read where the system gives none: the songs decide too.
        let withId = [SourceNaming.Recorded(name: "USB", root: mount, identity: Self.a, files: files(Self.songsOfA))]
        #expect(SourceNaming.choose("USB", root: back, found: Self.none, recorded: withId) == "USB")
        #expect(SourceNaming.choose("USB", root: mount, found: Self.none, recorded: withId) == "USB 2")

        // More than half of its songs, each at its path with its size: two of four is not enough, three is.
        let half = root.appendingPathComponent("half"), most = root.appendingPathComponent("most")
        try stick(half, Array(Self.songsOfA.prefix(2)) + ["Peak/01 Three.mp3"].map { "x/" + $0 })
        try stick(most, Array(Self.songsOfA.prefix(3)))
        #expect(!SourceNaming.holdsMostOf(files(Self.songsOfA), at: half))
        #expect(SourceNaming.holdsMostOf(files(Self.songsOfA), at: most))
        // The same paths with other sizes are other files.
        let resized = root.appendingPathComponent("resized")
        try stick(resized, Self.songsOfA, bytes: 11)
        #expect(!SourceNaming.holdsMostOf(files(Self.songsOfA), at: resized))
        // A source with no known files is never the same by evidence.
        #expect(!SourceNaming.holdsMostOf([], at: most))
        // A folder on the computer's own disk is the same folder at the same path, songs or none.
        let own = SourceIdentity.Found(identity: nil, ownDisk: true)
        let folder = [SourceNaming.Recorded(name: "Music", root: mount, identity: nil, files: [])]
        #expect(SourceNaming.choose("Music", root: mount, found: own, recorded: folder) == "Music")
        #expect(SourceNaming.choose("Music", root: mount, found: Self.none, recorded: folder) == "Music 2")
    }

    /// A crate recorded before identities were kept, as the window and the engine weigh it (`addRequest`): its own
    /// stick is found by its songs, a stranger with the same name and path is a new source, and each request carries
    /// the stick's identity.
    @Test func anOldRecordMeetsItsOwnStickAndAStranger() throws {
        let root = try scratch("ids-old")
        let mount = root.appendingPathComponent("USB")
        let home = DeskHome(root: root.appendingPathComponent("home"))
        let info0 = try home.shelf.make(name: "Friday")
        var info = try #require(home.shelf.info(info0.id))
        info.sourceRoots["USB"] = mount.path
        try home.shelf.save(info)
        let tracks = Self.songsOfA.enumerated().map { i, rel in
            entry(String(repeating: "\(i + 1)", count: 16), "Song \(i + 1)", disc: "USB",
                  folder: String(rel.split(separator: "/")[0]), track: i + 1, rel: rel)
        }
        try CrateWriter.write(crate(tracks), to: home.shelf.package(info.id))
        // A crate.json of before: no source_ids in it at all.
        let kept = try String(contentsOf: home.shelf.file(CrateShelf.infoFile, of: info.id), encoding: .utf8)
        #expect(!kept.contains("source_ids"))
        let s = DeskSession(home: home)
        #expect(s.current?.id == info.id && s.current?.sourceIds.isEmpty == true)

        try stick(mount, ["01 Other.mp3", "02 Other.mp3"])
        let stranger = s.addRequest(mount, name: "USB", identify: { _ in Self.onB })
        #expect(stranger.source == "USB 2" && stranger.volume == Self.b)

        try FileManager.default.removeItem(at: mount)
        try stick(mount, Self.songsOfA)
        let own = s.addRequest(mount, name: "USB", identify: { _ in Self.onA })
        #expect(own.source == "USB" && own.volume == Self.a)
    }

    @Test func identitiesAreKeptOnlyByAdditionAndFollowTheSource() throws {
        // A crate.json written before has none, and reads.
        let old = Data(#"{"id":"x","name":"Friday","created_at":1,"opened_at":2,"source_roots":{"USB":"/Volumes/USB"},"discs":{}}"#.utf8)
        var info = try JSONDecoder().decode(CrateInfo.self, from: old)
        #expect(info.sourceIds.isEmpty && info.sourceRoots["USB"] == "/Volumes/USB")
        // Written back with none, it has no new field.
        #expect(!String(decoding: try JSONEncoder().encode(info), as: UTF8.self).contains("source_ids"))
        // With one, it goes and comes back, and follows a rename and a removal.
        info.sourceIds["USB"] = Self.a
        let again = try JSONDecoder().decode(CrateInfo.self, from: try JSONEncoder().encode(info))
        #expect(again == info)
        info.renameSource("USB", to: "Friday stick")
        #expect(info.sourceIds["Friday stick"] == Self.a && info.sourceIds["USB"] == nil)
        info.forget(source: "Friday stick")
        #expect(info.sourceIds.isEmpty)
        // Identities in a form this desk does not know are no identities; the crate still reads, and so does a field
        // it has never heard of.
        let later = Data(#"{"id":"x","name":"Friday","created_at":1,"opened_at":2,"source_roots":{},"discs":{},"source_ids":{"USB":"some-later-form"},"later":true}"#.utf8)
        #expect(try JSONDecoder().decode(CrateInfo.self, from: later).sourceIds.isEmpty)

        // A stopped run kept before has no identity, and reads; one asked for on stick A does not carry on with B.
        let pending = Data(#"{"folder":"/Volumes/USB","source":"USB"}"#.utf8)
        var r = try JSONDecoder().decode(RunRequest.self, from: pending)
        #expect(r.volume == nil)
        #expect(!String(decoding: try JSONEncoder().encode(r), as: UTF8.self).contains("volume"))
        #expect(!DeskRun.otherDrive(r, identify: { _ in Self.onB }))
        r.volume = Self.a
        #expect(DeskRun.otherDrive(r, identify: { _ in Self.onB }))
        #expect(!DeskRun.otherDrive(r, identify: { _ in Self.onA }) && !DeskRun.otherDrive(r, identify: { _ in Self.none }))
    }

    @Test func theCratesOwnSourcesAreWeighedWithTheFilesTheyHold() throws {
        var info = CrateInfo(id: "x", name: "Friday", createdAt: 1, openedAt: 1,
                             sourceRoots: ["USB": "/Volumes/USB", "Music CD": "/dev/disk9"],
                             discs: ["Music CD": "toc"], sourceIds: ["USB": Self.a])
        let one = entry("1111111111111111", "One", disc: "USB", folder: "House", track: 1, rel: "House/01 One.mp3",
                        others: [.init(disc: "Brought in", folder: "", track: 3)])
        var c = crate([one, entry("2222222222222222", "Two", disc: "Music CD", folder: "", track: 1, rel: nil)])
        c.tracks[0].file.bytes = 1234
        var paths = PlacePaths()
        paths.byId["1111111111111111"] = [.init(source: "USB", folder: "House", rel: "House/01 One.mp3"),
                                          .init(source: "USB", folder: "Copies", rel: "Copies/One.mp3")]
        let r = info.recordedSources(crate: c, paths: paths)
        // The music CD is left out; a source only the crate names (brought in from elsewhere) is in, with nothing known.
        #expect(r.map(\.name) == ["Brought in", "USB"])
        #expect(r[0].root == nil && r[0].identity == nil && r[0].files.isEmpty)
        #expect(r[1].identity == Self.a && r[1].files == [.init(rel: "Copies/One.mp3", bytes: 1234), .init(rel: "House/01 One.mp3", bytes: 1234)])
        // The music CD's name is never taken by a drive.
        info.sourceIds = [:]
        #expect(info.sourceName("Music CD", root: URL(fileURLWithPath: "/Volumes/Music CD"), crate: c, paths: paths,
                                identify: { _ in Self.onB }) == "Music CD 2")
    }

    #if os(macOS)
    /// The real reader on this Mac: the computer's own disk is its own disk, and a place on it has an identity.
    @Test func theSystemSaysWhatAPlaceIsOn() throws {
        let here = try scratch("ids-real")
        let found = SourceIdentity.read(here)
        #expect(found.ownDisk)
        #expect(found.identity?.volume.isEmpty == false)
        // The same folder twice gives the same identity; a folder inside it another place on the same volume.
        let inner = here.appendingPathComponent("Inner")
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        let f2 = SourceIdentity.read(inner)
        #expect(SourceIdentity.read(here) == found)
        #expect(f2.identity?.volume == found.identity?.volume && f2.identity?.inside == (found.identity?.inside ?? "") + "/Inner")
    }
    #endif

    @Test func aPathBelowAVolumesTop() {
        #expect(SourceIdentity.inside("/Volumes/USB", below: "/Volumes/USB", separator: "/") == "")
        #expect(SourceIdentity.inside("/Volumes/USB/Sets/Music/", below: "/Volumes/USB", separator: "/") == "Sets/Music")
        #expect(SourceIdentity.inside("E:\\Sets\\Music", below: "E:\\", separator: "\\") == "Sets/Music")
        // A drive's top on Windows, written either way and in either case, is that top.
        #expect(SourceIdentity.inside("e:/Sets/Music", below: "E:\\", separator: "\\") == "Sets/Music")
        #expect(SourceIdentity.inside("E:\\", below: "E:\\", separator: "\\") == "")
        #expect(SourceIdentity.inside("E:", below: "E:\\", separator: "\\") == "")
        #if os(Windows)
        // Two spellings of one drive's top are one place, and neither becomes a path below the working folder.
        #expect(SourceNaming.comparablePath(URL(fileURLWithPath: "E:\\")) == SourceNaming.comparablePath(URL(fileURLWithPath: "e:/")))
        #expect(SourceNaming.comparablePath(URL(fileURLWithPath: "E:\\")) == "e:\\")
        #endif
        #expect(SourceIdentity.inside("/home/dj/Music", below: "/", separator: "/") == "home/dj/Music")
    }
}

/// The observed sequence, as runs: stick A read, taken out, stick B (another stick of the same name) put in at the
/// same path and added, both in at once, then each alone again. No song of either is ever lost or doubled.
@Suite(.enabled(if: Engine.available, "needs ONNX Runtime and the Beat This! model"))
struct SticksWithOneNameRunTests {
    /// The sticks plugged in now, by the path each is mounted at.
    final class Plugged { var at: [String: SourceIdentity] = [:] }

    @Test func twoSticksNamedNoNameKeepEachOthersSongs() async throws {
        let root = try scratch("ids-run")
        let fm = FileManager.default
        let mount = root.appendingPathComponent("Volumes/USB"), second = root.appendingPathComponent("Volumes/USB 1")
        let shelfA = root.appendingPathComponent("A"), shelfB = root.appendingPathComponent("B")
        try fm.createDirectory(at: shelfA.appendingPathComponent("House"), withIntermediateDirectories: true)
        try fm.createDirectory(at: shelfB, withIntermediateDirectories: true)
        try fm.createDirectory(at: mount.deletingLastPathComponent(), withIntermediateDirectories: true)
        // The test track's first 16 s (a steady 124 BPM beat), at three levels: three songs, kept short.
        let buffer = TestTrack.render()
        let cut = Array(buffer.samples.prefix(16 * TestTrack.rate * buffer.channelCount))
        func song(_ gain: Float) -> Data {
            TestTrack.wav(AudioBuffer(sampleRate: buffer.sampleRate, channelCount: buffer.channelCount, samples: cut.map { $0 * gain }))
        }
        try song(1).write(to: shelfA.appendingPathComponent("House/01 One.wav"))
        try song(0.8).write(to: shelfA.appendingPathComponent("House/02 Two.wav"))
        try song(0.6).write(to: shelfB.appendingPathComponent("01 Three.wav"))

        // Which stick is at which path: the seam the system's reader stands behind.
        let plugged = Plugged()
        let identify: SourceIdentity.Reader = { url in
            let p = url.standardizedFileURL.path
            return .init(identity: plugged.at.first { p == $0.key || p.hasPrefix($0.key + "/") }?.value, ownDisk: false)
        }
        func plug(_ stick: URL, _ id: SourceIdentity, at path: URL) throws {
            try fm.moveItem(at: stick, to: path); plugged.at[path.standardizedFileURL.path] = id
        }
        func unplug(_ path: URL, to stick: URL) throws {
            try fm.moveItem(at: path, to: stick); plugged.at[path.standardizedFileURL.path] = nil
        }

        let home = DeskHome(root: root.appendingPathComponent("home"))
        let analyser = try Builder.makeAnalyser(jobs: 1)
        let s = DeskSession(home: home)
        func add(_ path: URL) async throws -> RunReport {
            let request = s.addRequest(path, name: "USB", identify: identify)
            let info = try s.crateForRun(request)
            let run = DeskRun(home: home, crateId: info.id, request: request, jobs: 1, device: "Mac15,6", analyser: analyser,
                              signer: nil, printer: DeskRun.portablePrint)
            run.identify = identify
            let (saved, report) = try await CPUTurns.exclusive { try run.run() }
            s.runEnded(info.id, saved: saved)
            return report
        }
        func bySource() -> [String: Int] {
            var n: [String: Int] = [:]
            for t in s.crate?.tracks ?? [] { for p in Set(t.ident.allPlaces.compactMap(\.disc)) { n[p, default: 0] += 1 } }
            return n
        }
        let A = SourceIdentityTests.a, B = SourceIdentityTests.b

        // 1. Stick A alone.
        try plug(shelfA, A, at: mount)
        #expect(try await add(mount).wentIn == 2)
        #expect(bySource() == ["USB": 2] && s.current?.sourceIds["USB"] == A)
        // As if recorded before identities were kept: the next read has only the songs to go by.
        var info = try #require(s.current)
        info.sourceIds = [:]
        try home.shelf.save(info)
        _ = s.show(info.id)
        try unplug(mount, to: shelfA)

        // 2. Stick B alone, at the same path: a new source; A's songs stay.
        try plug(shelfB, B, at: mount)
        #expect(try await add(mount).wentIn == 1)
        #expect(bySource() == ["USB": 2, "USB 2": 1] && s.crate?.tracks.count == 3)
        #expect(s.current?.sourceIds["USB 2"] == B && s.current?.sourceIds["USB"] == nil)
        try unplug(mount, to: shelfB)

        // 3. Stick A alone again, at that path: found by its songs, and its identity learned.
        try plug(shelfA, A, at: mount)
        _ = try await add(mount)
        #expect(bySource() == ["USB": 2, "USB 2": 1] && s.current?.sourceIds["USB"] == A)
        try unplug(mount, to: shelfA)

        // 4. Both in: B where A was, A at the second path. Each is read into its own source.
        try plug(shelfB, B, at: mount)
        try plug(shelfA, A, at: second)
        #expect(s.addRequest(second, name: "USB", identify: identify).source == "USB")
        #expect(s.addRequest(mount, name: "USB", identify: identify).source == "USB 2")
        _ = try await add(second)
        #expect(bySource() == ["USB": 2, "USB 2": 1] && s.crate?.tracks.count == 3)
        #expect(s.crate?.tracks.allSatisfy { $0.ident.otherPlaces.isEmpty } == true)
        #expect(s.current?.roots["USB"]?.standardizedFileURL.path == second.standardizedFileURL.path)

        // A run asked for on A does not carry on with B at A's path.
        var asked = s.addRequest(second, name: "USB", identify: identify)
        asked.folder = mount.path
        #expect(!DeskRun.canCarryOn(asked, home: home, identify: identify))
    }
}
