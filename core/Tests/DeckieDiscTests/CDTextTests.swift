import Foundation
import Testing
import DeckieTestSupport
@testable import DeckieDisc

/// The CD-Text decoder on packs made from the format's description (DiscFixture), whole, damaged and partial.
@Suite struct CDTextTests {
    static let latin1 = DiscFixture.latin1
    /// A disc called "Friday night" by "DJ Vera", with three songs.
    static func friday(titles: [String] = ["Friday night", "Night drive", "Café Ünder", "Low tide"],
                       performers: [String] = ["DJ Vera", "Artist A", "Artist B", "Artist C"]) -> [[UInt8]] {
        DiscFixture.packs([(0x80, titles.map(latin1)), (0x81, performers.map(latin1))], lastSong: UInt8(titles.count - 1))
    }

    @Test func checkIsTheFormatsCRC() {
        // The check over a pack is CRC-16/XMODEM (0x1021 from 0), inverted; the standard check value of "123456789" is 0x31C3.
        #expect(CDText.crc16(Array("123456789".utf8)) == 0x31C3)
        for p in Self.friday() { #expect(CDText.checkPasses(p[...])) }
    }

    @Test func wholeDisc() throws {
        let t = CDText.decode(DiscFixture.response(Self.friday()))
        let b = try #require(t.main)
        #expect(t.checked)
        #expect(t.packsDamaged == 0)
        #expect(b.discTitle == "Friday night")
        #expect(b.discPerformer == "DJ Vera")
        #expect(b.titles == [0: "Friday night", 1: "Night drive", 2: "Café Ünder", 3: "Low tide"])
        #expect(b.performers[2] == "Artist B")
        #expect(b.characters == .latin1)
        #expect(b.language == 0x09)
        #expect(b.firstSong == 1 && b.lastSong == 3)
        #expect(b.damaged.isEmpty)
        #expect(t.hasNames)
    }

    @Test func barePacksWithNoHeader() throws {
        let t = CDText.decode(Self.friday().flatMap { $0 })
        #expect(t.main?.titles[3] == "Low tide")
    }

    @Test func longTitlesCrossPacks() throws {
        let long = "An extended mix that runs well past one pack (and two)"
        let t = CDText.decode(DiscFixture.response(Self.friday(titles: ["Disc", long, "B", long + " again"])))
        #expect(t.main?.titles[1] == long)
        #expect(t.main?.titles[3] == long + " again")
    }

    @Test func tabMeansSameAsBefore() throws {
        let t = CDText.decode(DiscFixture.response(Self.friday(performers: ["Various", "Artist A", "\t", "\t"])))
        #expect(t.main?.performers[2] == "Artist A")
        #expect(t.main?.performers[3] == "Artist A")
    }

    @Test func aDamagedPackLosesOnlyItsText() throws {
        var packs = Self.friday(titles: ["Friday night", "A title long enough to take a second pack", "Short", "Low tide"])
        // Spoil one title pack's bytes: its check now fails.
        let i = packs.firstIndex { $0[0] == 0x80 && $0[1] == 1 && $0[3] & 0x0F > 0 }!
        packs[i][8] ^= 0xFF
        let t = CDText.decode(DiscFixture.response(packs))
        let b = try #require(t.main)
        #expect(t.packsDamaged == 1)
        #expect(b.titles[1] == nil)                 // never shown with a hole in it
        #expect(b.damaged[0x80]?.contains(1) == true)
        #expect(b.titles[0] == "Friday night")
        #expect(b.titles[3] == "Low tide")          // the reading starts again where the next pack says
        #expect(b.performers.count == 4)
    }

    @Test func aMissingPackIsNoticedFromTheNextOnesPlace() throws {
        var packs = Self.friday(titles: ["Friday night", "One", "Two", "A title long enough to need more than one pack", "Five"])
        packs.remove(at: 1)   // the second title pack: the end of "Friday night", then "One" and the start of "Two"
        let t = CDText.decode(DiscFixture.response(packs))
        let b = try #require(t.main)
        #expect(t.packsDamaged == 0)
        #expect(b.titles[0] == nil)
        #expect(b.titles[4] == "Five")
        #expect(!(b.damaged[0x80] ?? []).isEmpty)
    }

    @Test func cutOffMidPack() throws {
        let bytes = DiscFixture.response(Self.friday())
        let t = CDText.decode(Array(bytes.prefix(bytes.count - 30)))
        // The header says more than came: what came whole is read; nothing is made up.
        #expect(t.main?.titles[0] == "Friday night")
        for (_, v) in t.main?.titles ?? [:] { #expect(!v.isEmpty) }
    }

    @Test func checksAllZeroAreReadAsTheyAre() throws {
        let packs = Self.friday().map { Array($0.prefix(16)) + [0, 0] }
        let t = CDText.decode(DiscFixture.response(packs))
        #expect(!t.checked)
        #expect(t.main?.titles[1] == "Night drive")
    }

    @Test func noTextAtAll() {
        let t = CDText.decode([0, 2, 0, 0])
        #expect(t.blocks.isEmpty)
        #expect(!t.hasNames)
        #expect(TextReading.from([0, 2, 0, 0]) == .none)
    }

    @Test func everyPackDamagedIsNotNone() {
        var packs = Self.friday()
        for i in packs.indices { packs[i][17] ^= 0x55 }
        #expect(TextReading.from(DiscFixture.response(packs)).code == "drive")
    }

    @Test func plainASCII() throws {
        let packs = DiscFixture.packs([(0x80, ["Disc", "Song"].map { Array($0.utf8) })], charset: 0x01, lastSong: 1)
        let t = CDText.decode(DiscFixture.response(packs))
        #expect(t.main?.characters == .ascii)
        #expect(t.main?.titles[1] == "Song")
    }

    @Test func japaneseInMSJIS() throws {
        // "夜" and "曲" in Shift-JIS (MS-JIS): 0x96E9, 0x8BC8; two bytes a character, two zero bytes at each end.
        let night: [UInt8] = [0x96, 0xE9], song: [UInt8] = [0x8B, 0xC8]
        let packs = DiscFixture.packs([(0x80, [night, night + song])], charset: 0x80, doubleByte: true, lastSong: 1,
                                      language: 0x69)
        let t = CDText.decode(DiscFixture.response(packs))
        let b = try #require(t.main)
        #expect(b.characters == .msJIS)
        #expect(b.language == 0x69)
        #expect(b.titles[0] == "夜")
        #expect(b.titles[1] == "夜曲")
    }

    @Test func charactersDeskDoesNotReadAreLeftOut() {
        let packs = DiscFixture.packs([(0x80, [[0xB0, 0xA1], [0xB0, 0xA2]])], charset: 0x81, doubleByte: true, lastSong: 1)
        let r = TextReading.from(DiscFixture.response(packs))
        #expect(r.code == "drive")
    }

    @Test func isrcsAndBarcode() throws {
        let packs = DiscFixture.packs([(0x80, ["D", "S1", "S2"].map(Self.latin1)),
                                       (0x8E, ["0012345678905", "USABC0100001", "USABC0100002"].map { Array($0.utf8) })], lastSong: 2)
        let b = try #require(CDText.decode(DiscFixture.response(packs)).main)
        #expect(b.barcode == "0012345678905")
        #expect(b.isrcs == [1: "USABC0100001", 2: "USABC0100002"])
    }

    @Test func twoLanguagesTwoBlocks() throws {
        let en = DiscFixture.packs([(0x80, ["Night", "One"].map(Self.latin1))], block: 0, lastSong: 1)
        let de = DiscFixture.packs([(0x80, ["Nacht", "Eins"].map(Self.latin1))], block: 1, lastSong: 1, language: 0x08)
        let t = CDText.decode(DiscFixture.response(en + de))
        #expect(t.blocks.count == 2)
        #expect(t.main?.titles[0] == "Night")
        #expect(t.blocks[1].titles[1] == "Eins")
    }

    @Test func noSizeInformationMeansLatin1() throws {
        let packs = DiscFixture.packs([(0x80, ["Disc", "Ça va"].map(Self.latin1))], withSizeInfo: false)
        #expect(CDText.decode(DiscFixture.response(packs)).main?.titles[1] == "Ça va")
    }
}

/// The table of contents: format 0 and format 2, and how songs are cut from it.
@Suite struct DiscTOCTests {
    @Test func format0() throws {
        let toc = try DiscTOC.format0(DiscFixture.toc(starts: [0, 15_000, 30_000], leadOut: 45_000))
        #expect(toc.tracks.map(\.number) == [1, 2, 3])
        #expect(toc.songs.map(\.sectors) == [15_000, 15_000, 15_000])
        #expect(toc.songs[0].seconds == 200)
        #expect(toc.audioSeconds == 600)
    }

    @Test func aHiddenSongBeforeSongOneBelongsToIt() throws {
        let toc = try DiscTOC.format0(DiscFixture.toc(starts: [3_000, 10_000], leadOut: 20_000))
        #expect(toc.songs[0].start == 0)
        #expect(toc.songs[0].end == 10_000)
    }

    @Test func anEnhancedCDsDataTrackIsLeftOut() throws {
        let toc = try DiscTOC.format0(DiscFixture.toc(starts: [0, 20_000, 50_000], leadOut: 90_000, data: [3]))
        #expect(toc.songs.map(\.number) == [1, 2])
        #expect(toc.songs[1].end == 50_000 - 11_400)
    }

    @Test func format2() throws {
        // Session 1: tracks 1 and 2 at 00:02:00 and 03:00:00, lead-out at 06:00:00.
        func entry(_ point: UInt8, _ m: UInt8, _ s: UInt8, _ f: UInt8, control: UInt8 = 0) -> [UInt8] {
            [1, 0x10 | control, 0, point, 0, 0, 0, 0, m, s, f]
        }
        var body = entry(0xA0, 1, 0, 0) + entry(0xA1, 2, 0, 0) + entry(0xA2, 6, 0, 0) + entry(1, 0, 2, 0) + entry(2, 3, 0, 0)
        let n = body.count + 2
        body = [UInt8(n >> 8), UInt8(n & 0xFF), 1, 1] + body
        let toc = try DiscTOC.format2(body)
        #expect(toc.tracks.map(\.start) == [0, 3 * 60 * 75 - 150])
        #expect(toc.leadOut == 6 * 60 * 75 - 150)
    }

    @Test func idIsTheSameForTheSameDiscOnly() throws {
        let a = try DiscTOC.format0(DiscFixture.toc(starts: [0, 15_000], leadOut: 30_000))
        let b = try DiscTOC.format0(DiscFixture.toc(starts: [0, 15_000], leadOut: 30_000))
        let c = try DiscTOC.format0(DiscFixture.toc(starts: [0, 15_001], leadOut: 30_000))
        #expect(a.id == b.id)
        #expect(a.id != c.id)
        #expect(a.id.hasPrefix("cd-") && a.id.count == 19)
    }

    @Test func tooShortIsAnError() {
        #expect(throws: DiscError.self) { try DiscTOC.format0([0, 2, 1, 1]) }
    }
}

/// Copying songs off a disc through the stand-in drive: cut where the table says, a second try, silence counted.
@Suite struct CopyTests {
    static func scratch(_ name: String) -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("deckie-disc-\(name)-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static func tone(_ sectors: Int, value: Int16) -> [Int16] { [Int16](repeating: value, count: sectors * 588 * 2) }

    @Test func copiesEachSongAsTheTableCutsIt() throws {
        let dir = Self.scratch("copy")
        defer { try? FileManager.default.removeItem(at: dir) }
        let disc = dir.appendingPathComponent("disc")
        try DiscFixture.writeStandIn(disc, songs: [Self.tone(10, value: 100), Self.tone(7, value: 200)],
                                     cdText: DiscFixture.response(CDTextTests.friday(titles: ["D", "A", "B"], performers: ["P", "X", "Y"])))
        let cd = SectorMusicCD(location: disc.path, device: StandInDrive(folder: disc))
        let toc = try cd.tableOfContents()
        #expect(toc.songs.map(\.sectors) == [10, 7])
        guard case let .names(text) = cd.readText() else { Issue.record("no names"); return }
        #expect(text.main?.titles[2] == "B")
        let out = dir.appendingPathComponent("Track 02.wav")
        var seen = 0
        let damaged = try cd.copy(toc.songs[1], to: out) { done, _ in seen = done }
        #expect(damaged == 0)
        #expect(seen == 7)
        let wav = [UInt8](try Data(contentsOf: out))
        #expect(wav.count == 44 + 7 * 2352)
        #expect(String(decoding: wav[0..<4], as: UTF8.self) == "RIFF")
        #expect(wav[44] == 200 && wav[45] == 0)
        #expect(!FileManager.default.fileExists(atPath: out.path + ".part"))
    }

    @Test func aSectorThatFailsOnceIsReadAgain() throws {
        let dir = Self.scratch("retry")
        defer { try? FileManager.default.removeItem(at: dir) }
        let disc = dir.appendingPathComponent("disc")
        try DiscFixture.writeStandIn(disc, songs: [Self.tone(30, value: 9)], cdText: nil)
        try "5\nalways 25\n".write(to: disc.appendingPathComponent("bad.txt"), atomically: true, encoding: .utf8)
        let cd = SectorMusicCD(location: disc.path, device: StandInDrive(folder: disc))
        #expect(cd.readText() == .none)
        let out = dir.appendingPathComponent("Track 01.wav")
        let damaged = try cd.copy(try cd.tableOfContents().songs[0], to: out) { _, _ in }
        #expect(damaged == 1)
        let wav = [UInt8](try Data(contentsOf: out))
        #expect(wav[44 + 5 * 2352] == 9)        // read on the second try
        #expect(wav[44 + 25 * 2352] == 0)       // silence where the sector never came
        #expect(wav[44 + 26 * 2352] == 9)
    }

    @Test func aRefusedTextCommandIsNotNoNames() throws {
        let dir = Self.scratch("refused")
        defer { try? FileManager.default.removeItem(at: dir) }
        try DiscFixture.writeStandIn(dir, songs: [Self.tone(3, value: 1)], cdText: nil)
        try Data().write(to: dir.appendingPathComponent("cdtext.refused"))
        let cd = SectorMusicCD(location: dir.path, device: StandInDrive(folder: dir))
        #expect(cd.readText().code == "drive")
    }

    @Test func listingStandIns() throws {
        let dir = Self.scratch("list")
        defer { try? FileManager.default.removeItem(at: dir) }
        try DiscFixture.writeStandIn(dir.appendingPathComponent("E"), songs: [Self.tone(75, value: 1), Self.tone(150, value: 2)], cdText: nil)
        let env = [MusicCDs.standInVariable: dir.path]
        let found = MusicCDs.list(environment: env)
        #expect(found.count == 1)
        #expect(found.first?.drive == "E")
        #expect(found.first?.songs == 2)
        #expect(found.first?.seconds == 3)
        let cd = try MusicCDs.open(found[0].location, environment: env)
        #expect(try cd.tableOfContents().id == found[0].discId)
    }

    /// The system's own calls, against a drive that is not there: each fails with the system's error, cleanly. This
    /// is all that can be run with no drive; no disc has been read by these calls.
    @Test func systemCallsWithNoDrive() {
        #if os(Windows)
        let path = "\\\\.\\Q:"
        #elseif os(macOS)
        let path = "/dev/rdisk999"
        #else
        let path = "/dev/sr99"
        #endif
        #expect(throws: DiscError.self) { _ = try SystemDrive(path: path) }
    }
}
