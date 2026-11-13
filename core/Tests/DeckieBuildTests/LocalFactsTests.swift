import Foundation
import Testing
import DeckieCore
import DeckieCrate
@testable import DeckieBuild

/// Keys and names already on the computer (D30): the notations, the tags, the DJ programs' libraries (built here from
/// each format's public description; none was checked against the real programs), the matching, and the rules for
/// which key wins and where a name comes from.
@Suite struct KeyNotationTests {
    @Test func musicalNamesWithSharpsFlatsAndModes() {
        let cases: [(String, String?)] = [
            ("Am", "8A"), ("A minor", "8A"), ("A Minor", "8A"), ("Amin", "8A"), ("A min", "8A"), ("am", "8A"), ("A-", "8A"),
            ("C", "8B"), ("C major", "8B"), ("Cmaj", "8B"), ("C Maj", "8B"), ("CM", "8B"),
            ("F#m", "11A"), ("F♯m", "11A"), ("Gbm", "11A"), ("G♭ minor", "11A"), ("F sharp minor", "11A"),
            ("Bb", "6B"), ("B flat", "6B"), ("Bbm", "3A"), ("Bm", "10A"), ("B", "1B"), ("Db", "3B"), ("C#", "3B"),
            ("Ebmin", "2A"), ("D#m", "2A"), ("Abm", "1A"), ("G#m", "1A"), ("E", "12B"), ("Em", "9A"),
        ]
        for (t, want) in cases { #expect(KeyNotation.camelot(t) == want, "\(t)") }
    }

    @Test func camelotAndOpenKey() {
        let cases: [(String, String?)] = [
            ("8A", "8A"), ("08A", "8A"), ("8a", "8A"), ("12B", "12B"), ("1b", "1B"), (" 5A ", "5A"),
            ("1m", "8A"), ("1d", "8B"), ("6d", "1B"), ("12m", "7A"), ("4m", "11A"), ("01m", "8A"),
        ]
        for (t, want) in cases { #expect(KeyNotation.camelot(t) == want, "\(t)") }
    }

    @Test func whatIsNotAKey() {
        for t in ["", "  ", "13A", "0A", "8C", "H", "Am7", "a", "Off", "o", "Dorian", "8A/9A", "123A", "C# lydian"] {
            #expect(KeyNotation.camelot(t) == nil, "\(t)")
        }
        #expect(KeyNotation.wheelOnly("Am") == nil)
        #expect(KeyNotation.wheelOnly("8A") == "8A")
    }

    @Test func engineDJsNumbersGoRoundTheWheel() {
        #expect(DJLibrary.engineKey(0) == "8B")   // C major
        #expect(DJLibrary.engineKey(1) == "8A")   // A minor
        #expect(DJLibrary.engineKey(2) == "9B")   // G major
        #expect(DJLibrary.engineKey(7) == "11A")  // F# minor
        #expect(DJLibrary.engineKey(19) == "5A")  // C minor
        #expect(DJLibrary.engineKey(23) == "7A")  // D minor
        #expect(DJLibrary.engineKey(24) == nil && DJLibrary.engineKey(-1) == nil)
    }
}

@Suite struct KeyTagTests {
    typealias T = FileTagsTests

    /// An ID3v2.3 frame with arbitrary bytes after the frame header.
    static func frame(_ id: String, _ data: [UInt8]) -> [UInt8] { Array(id.utf8) + T.be32(data.count) + [0, 0] + data }
    static func tag(_ frames: [[UInt8]]) -> [UInt8] {
        let body = frames.flatMap { $0 } + [UInt8](repeating: 0, count: 8)
        return Array("ID3".utf8) + [3, 0, 0] + T.synchsafe(body.count) + body
    }

    @Test func standardKeyTagAlbumAndTrackNumber() throws {
        let t = Self.tag([Self.frame("TKEY", [0] + Array("F#m".utf8)), Self.frame("TALB", [0] + Array("An Album".utf8)),
                          Self.frame("TRCK", [0] + Array("02/12".utf8)), Self.frame("TIT2", [0] + Array("Song".utf8))])
        let tags = FileTags.read(try T.write(t + T.mpegFrame, "tkey.mp3"))
        #expect(tags.key == "F#m" && tags.album == "An Album" && tags.trackNumber == 2 && tags.title == "Song")
    }

    @Test func txxxInitialKeyAndMixedInKeysComment() throws {
        let txxx = Self.frame("TXXX", [0] + Array("INITIALKEY".utf8) + [0] + Array("8A".utf8))
        let comm = Self.frame("COMM", [0] + Array("eng".utf8) + [0] + Array("1A - Energy 6".utf8))
        let itunes = Self.frame("COMM", [0] + Array("eng".utf8) + Array("iTunNORM".utf8) + [0] + Array(" 0000 0000".utf8))
        let tags = FileTags.read(try T.write(Self.tag([itunes, txxx, comm]) + T.mpegFrame, "mik.mp3"))
        #expect(tags.key == "8A")
        #expect(tags.comment == "1A - Energy 6")
        #expect(LocalNames.key(inComment: tags.comment!) == "1A")
        // ffmpeg writes a comment as TXXX "comment".
        let ff = Self.frame("TXXX", [0] + Array("comment".utf8) + [0] + Array("4A - Energy 6".utf8))
        #expect(FileTags.read(try T.write(Self.tag([ff]) + T.mpegFrame, "ff.mp3")).comment == "4A - Energy 6")
    }

    @Test func utf16CommentWithItsOwnByteOrderMark() throws {
        let desc = T.utf16WithBOM("") + [0, 0]
        let text = T.utf16WithBOM("5A - Energy 7")
        let comm = Self.frame("COMM", [1] + Array("eng".utf8) + desc + text)
        #expect(FileTags.read(try T.write(Self.tag([comm]) + T.mpegFrame, "u16.mp3")).comment == "5A - Energy 7")
    }

    @Test func vorbisInitialKeyAndComment() {
        func s(_ x: String) -> [UInt8] { T.le32(x.utf8.count) + Array(x.utf8) }
        let block = s("vendor") + T.le32(4) + s("INITIALKEY=Abm") + s("COMMENT=Energy 5 - 1A") + s("ALBUM=Disc")
            + s("TRACKNUMBER=7")
        let tags = FileTags.vorbisComment(Data(block))
        #expect(tags.key == "Abm" && tags.comment == "Energy 5 - 1A" && tags.album == "Disc" && tags.trackNumber == 7)
        #expect(LocalNames.key(inComment: "Energy 5 - 1A") == "1A")
    }

    @Test func wavListInfoBesideAnID3Chunk() throws {
        func chunk(_ id: String, _ body: [UInt8]) -> [UInt8] { Array(id.utf8) + T.le32(body.count) + body + (body.count % 2 == 1 ? [0] : []) }
        let info = Array("INFO".utf8) + chunk("INAM", Array("Info Title".utf8) + [0]) + chunk("IART", Array("Info Artist".utf8) + [0])
            + chunk("IKEY", Array("keywords".utf8) + [0])
        let id3 = Self.tag([Self.frame("TKEY", [0] + Array("Dm".utf8))])
        let fmt = chunk("fmt ", [1, 0, 1, 0, 0x44, 0xAC, 0, 0, 0x88, 0x58, 1, 0, 2, 0, 16, 0])
        let body = Array("WAVE".utf8) + fmt + chunk("LIST", info) + chunk("id3 ", id3)
        let file = Array("RIFF".utf8) + T.le32(body.count) + body
        let tags = FileTags.read(try T.write(file, "info.wav"))
        #expect(tags.title == "Info Title" && tags.artist == "Info Artist" && tags.key == "Dm")
    }

    @Test func id3v1AtTheEndOfAnMP3() throws {
        func field(_ s: String, _ n: Int) -> [UInt8] { Array(s.utf8.prefix(n)) + [UInt8](repeating: 0, count: max(0, n - s.utf8.count)) }
        let v1 = Array("TAG".utf8) + field("Old Title", 30) + field("Old Artist", 30) + field("Old Album", 30) + field("1999", 4)
            + field("8A", 28) + [0, 3] + [0xFF]
        let tags = FileTags.read(try T.write(T.mpegFrame + v1, "v1.mp3"))
        #expect(tags.title == "Old Title" && tags.artist == "Old Artist" && tags.album == "Old Album")
        #expect(tags.trackNumber == 3 && tags.comment == "8A")
    }
}

@Suite struct LocalNamesTests {
    @Test func usableNames() {
        for t in ["Song A", "1999 (Remix)", "99 Problems", "Ü"] { #expect(LocalNames.isUsableTitle(t), "\(t)") }
        for t in ["", " ", "Track 01", "Track01", "track 1", "Audio Track 3", "Untitled", "Unknown", "07", "Piste 4"] {
            #expect(!LocalNames.isUsableTitle(t), "\(t)")
        }
        #expect(LocalNames.isUsableArtist("DJ Test"))
        for a in [nil, "", "Unknown Artist", "Various Artists", "VA", "various"] { #expect(!LocalNames.isUsableArtist(a)) }
    }

    @Test func fileNamePatterns() {
        #expect(LocalNames.fromFileName("02 Song A", number: 2) == ("Song A", nil))
        #expect(LocalNames.fromFileName("02 Song A", number: 5) == ("02 Song A", nil))
        #expect(LocalNames.fromFileName("02 Song A", number: nil) == ("02 Song A", nil))
        #expect(LocalNames.fromFileName("03. Artist B - Song B", number: 3) == ("Song B", "Artist B"))
        #expect(LocalNames.fromFileName("03 - Artist B - Song B", number: 3) == ("Song B", "Artist B"))
        #expect(LocalNames.fromFileName("07 Artist B - Song B", number: 3) == ("07 Artist B - Song B", nil))
        #expect(LocalNames.fromFileName("Artist C - Song C (Extended Mix)", number: 1) == ("Song C (Extended Mix)", "Artist C"))
        #expect(LocalNames.fromFileName("Artist_D_-_Song_D", number: nil) == ("Song D", "Artist D"))
        #expect(LocalNames.fromFileName("8A - 128 - Artist E - Song E", number: nil) == ("Song E", "Artist E"))
        #expect(LocalNames.fromFileName("1999", number: 1) == ("1999", nil))
        #expect(LocalNames.fromFileName("Track 01", number: 1) == ("Track 01", nil))
    }

    @Test func folderAsArtistOnlyWhenThePatternIsClear() {
        #expect(LocalNames.artist(fromFolder: "Artist F - The Album", fileName: "01 Song") == "Artist F")
        #expect(LocalNames.artist(fromFolder: "House", fileName: "01 Song") == nil)
        #expect(LocalNames.artist(fromFolder: "Artist F - The Album", fileName: "Song") == nil)
        #expect(LocalNames.artist(fromFolder: "Various Artists - Hits", fileName: "01 Song") == nil)
    }

    @Test func keysInCommentsAndTitles() {
        #expect(LocalNames.key(inComment: "8A") == "8A")
        #expect(LocalNames.key(inComment: "Am") == "8A")
        #expect(LocalNames.key(inComment: "8A - Energy 6") == "8A")
        #expect(LocalNames.key(inComment: "Energy 6 - 8A") == "8A")
        #expect(LocalNames.key(inComment: "Great tune for the warm-up") == nil)
        #expect(LocalNames.key(inComment: "Bought at the record fair - 2019") == nil)
        func inTitle(_ s: String) -> String? { LocalNames.key(inTitle: s).map { "\($0.camelot) \($0.title)" } }
        #expect(inTitle("8A - Song") == "8A Song")
        #expect(inTitle("8A - 128 - Song") == "8A Song")
        #expect(inTitle("Song - 1m") == "8A Song")
        #expect(LocalNames.key(inTitle: "Am - I Dreaming") == nil)
        #expect(LocalNames.key(inTitle: "Song") == nil)
    }

    @Test func cueSheetsPlaylistsAndNumberedLists() {
        let cue = """
        PERFORMER "Album Artist"
        TITLE "The Album"
        FILE "01 One.wav" WAVE
          TRACK 01 AUDIO
            TITLE "One"
            PERFORMER "Artist One"
        FILE "02 Two.wav" WAVE
          TRACK 02 AUDIO
            TITLE "Two"
        FILE "Mix.flac" WAVE
          TRACK 01 AUDIO
            TITLE "In the mix"
          TRACK 02 AUDIO
            TITLE "Also in the mix"
        """
        let c = LocalNames.cue(cue)
        #expect(c["01 one.wav"] == .init(title: "One", artist: "Artist One", origin: "cue"))
        #expect(c["02 two.wav"] == .init(title: "Two", artist: "Album Artist", origin: "cue"))
        #expect(c["mix.flac"] == .init(title: "The Album", artist: "Album Artist", origin: "cue"))

        let m = LocalNames.m3u("#EXTM3U\n#EXTINF:301,Artist M - Song M\nsub\\Track 01.mp3\n#EXTINF:200,Lonely\nother.mp3\n")
        #expect(m["track 01.mp3"] == .init(title: "Song M", artist: "Artist M", origin: "m3u"))
        #expect(m["other.mp3"] == .init(title: "Lonely", artist: nil, origin: "m3u"))

        let list = LocalNames.numberedList("Ripped by me\n\n01. Artist X - Song X\n02. Song Y\n03) Artist Z - Song Z\n")
        #expect(list[1] == .init(title: "Song X", artist: "Artist X", origin: "tracklist"))
        #expect(list[2] == .init(title: "Song Y", artist: nil, origin: "tracklist"))
        #expect(list.count == 3)
        #expect(LocalNames.numberedList("1. Rip with care\n5. Then check\n").isEmpty)
    }
}

/// The libraries, each built here as its documentation (or, for Serato, the published reverse engineering) describes it.
@Suite struct DJLibraryTests {
    static let here = URL(fileURLWithPath: "/Users/dj/Documents/lib/collection.nml")

    @Test func traktorCollection() throws {
        let nml = """
        <?xml version="1.0" encoding="UTF-8" standalone="no" ?>
        <NML VERSION="19"><HEAD COMPANY="www.native-instruments.com" PROGRAM="Traktor"></HEAD>
        <COLLECTION ENTRIES="3">
        <ENTRY MODIFIED_DATE="2026/11/1" TITLE="Song A" ARTIST="Artist A">
        <LOCATION DIR="/:Users/:dj/:Music/:House/:" FILE="01 Song A.mp3" VOLUME="Macintosh HD" VOLUMEID="abc"></LOCATION>
        <INFO BITRATE="320000" KEY="1m" FILESIZE="8123"></INFO><TEMPO BPM="124.000000"></TEMPO><MUSICAL_KEY VALUE="21"></MUSICAL_KEY>
        </ENTRY>
        <ENTRY TITLE="Win Song" ARTIST="Win Artist">
        <LOCATION DIR="/:Users/:dj/:Music/:" FILE="win.mp3" VOLUME="C:" VOLUMEID="C:"></LOCATION><INFO KEY="Ebm"></INFO>
        </ENTRY>
        <ENTRY TITLE="No key"><LOCATION DIR="/:Set/:" FILE="x.wav" VOLUME="STICK"></LOCATION><INFO KEY=""></INFO></ENTRY>
        </COLLECTION>
        <PLAYLISTS><NODE TYPE="FOLDER" NAME="$ROOT"></NODE></PLAYLISTS></NML>
        """
        let e = try DJLibrary.parse(.traktor, Data(nml.utf8), at: Self.here)
        #expect(e.count == 3)
        #expect(e[0].paths == ["/Users/dj/Music/House/01 Song A.mp3", "/Volumes/Macintosh HD/Users/dj/Music/House/01 Song A.mp3"])
        #expect(e[0].camelot == "8A" && e[0].keyAsWritten == "1m" && e[0].title == "Song A" && e[0].size == 8123 * 1024)
        #expect(e[1].paths == ["C:/Users/dj/Music/win.mp3"] && e[1].camelot == "2A")
        #expect(e[2].camelot == nil && e[2].paths.last == "/Volumes/STICK/Set/x.wav")
        #expect(throws: (any Error).self) { try DJLibrary.parse(.traktor, Data("<x/>".utf8), at: Self.here) }
    }

    @Test func virtualDJDatabase() throws {
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <VirtualDJ_Database Version="8.1">
         <Song FilePath="C:\\Users\\dj\\Music\\a.mp3" FileSize="5000">
          <Tags Author="Artist V" Title="Song V" Remix="Club Mix" Key="Am" Flag="1" />
          <Infos SongLength="300" />
          <Scan Version="801" Bpm="0.468750" Key="C" Flags="1" />
         </Song>
         <Song FilePath="\\Music\\b.mp3" FileSize="10">
          <Tags Title="Song W" />
          <Scan Key="G#m" />
         </Song>
        </VirtualDJ_Database>
        """
        let e = try DJLibrary.parse(.virtualDJ, Data(xml.utf8), at: URL(fileURLWithPath: "/Volumes/USB/VirtualDJ/database.xml"))
        #expect(e.count == 2)
        #expect(e[0].paths == ["C:/Users/dj/Music/a.mp3"] && e[0].camelot == "8A" && e[0].version == "Club Mix")
        #expect(e[0].artist == "Artist V" && e[0].size == 5000)
        #expect(e[1].paths == ["/Music/b.mp3"] && e[1].camelot == "1A")
    }

    @Test func engineDJLibraryThroughTheSQLiteReader() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/engine-m.db")
        let data = try Data(contentsOf: url)
        let db = try SQLiteReader(data: data)
        let t = try #require(try db.table("Track"))
        #expect(t.rows.count == 62)
        #expect(t.columns.first == "id" && t.columns.last == "lastEditTime" && t.columns.contains("key"))
        #expect(t.rows.map { $0["id"]?.integer } == (1...62).map { Int64($0) })
        let long = try #require(t.rows.first { $0["filename"]?.text == "long.mp3" })
        #expect(long["title"]?.text?.count == 844)
        #expect(t.rows[4]["bpmAnalyzed"]?.real == -7.5)
        #expect(t.rows[0]["lastEditTime"] == nil && t.rows[61]["lastEditTime"]?.text == "2026-11-13 10:00:00")
        #expect(try db.table("Information")?.rows.first?["schemaVersionMajor"]?.integer == 2)
        #expect(try db.table("Nothing") == nil)

        let at = URL(fileURLWithPath: "/Users/dj/Music/Engine Library/Database2/m.db")
        let e = try DJLibrary.parse(.engineDJ, data, at: at)
        #expect(e.count == 62)
        #expect(e[0].paths == ["/Users/dj/Music/Music/House/01 Song A.mp3"] && e[0].camelot == "8A" && e[0].size == 123456)
        #expect(e[1].camelot == "8B")
        #expect(e[2].paths == ["/Volumes/Stick/Set/Song C.flac"] && e[2].camelot == "7A" && e[2].title == nil)
    }

    @Test func sqliteReaderRefusesWhatIsNotADatabase() {
        #expect(throws: (any Error).self) { try SQLiteReader(data: Data("not a database at all, and long enough".utf8)) }
        #expect(SQLiteReader.columns(ofCreate: "CREATE TABLE \"x\" (\"a b\" TEXT, [c] INTEGER PRIMARY KEY, d, PRIMARY KEY (d))")
                    == (["a b", "c", "d"], "c"))
    }

    static func serato(_ fields: [(String, [UInt8])]) -> [UInt8] {
        fields.flatMap { Array($0.0.utf8) + FileTagsTests.be32($0.1.count) + $0.1 }
    }
    static func u16(_ s: String) -> [UInt8] { s.utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] } }

    @Test func seratoDatabase() throws {
        let track = Self.serato([("ttyp", Self.u16("mp3")), ("pfil", Self.u16("Users/dj/Music/s.mp3")), ("tsng", Self.u16("Song S")),
                                 ("tart", Self.u16("Artist S")), ("tkey", Self.u16("Bbm")), ("uadd", [0, 0, 0, 1])])
        let other = Self.serato([("pfil", Self.u16("Set/t.mp3")), ("tkey", Self.u16(""))])
        let db = Self.serato([("vrsn", Self.u16("2.0/Serato Scratch LIVE Database")), ("otrk", track), ("otrk", other)])
        let e = try DJLibrary.parse(.serato, Data(db), at: URL(fileURLWithPath: "/Volumes/USB/_Serato_/database V2"))
        #expect(e.count == 2)
        #expect(e[0].paths.first == "/Volumes/USB/Users/dj/Music/s.mp3" && e[0].paths.contains("/Users/dj/Music/s.mp3"))
        #expect(e[0].camelot == "3A" && e[0].title == "Song S" && e[0].artist == "Artist S")
        #expect(e[1].camelot == nil && e[1].paths.first == "/Volumes/USB/Set/t.mp3")
    }

    @Test func rekordboxExportAsALibrary() throws {
        let xml = """
        <DJ_PLAYLISTS Version="1.0.0"><COLLECTION Entries="1">
        <TRACK TrackID="1" Name="Song R" Artist="Artist R" Mix="Dub" Size="777" Tonality="5A" Location="file://localhost/Users/dj/Music/r.mp3"/>
        </COLLECTION></DJ_PLAYLISTS>
        """
        let e = try DJLibrary.parse(.rekordbox, Data(xml.utf8), at: Self.here)
        #expect(e == [DJLibraryEntry(paths: ["/Users/dj/Music/r.mp3"], title: "Song R", artist: "Artist R", version: "Dub",
                                     keyAsWritten: "5A", size: 777)])
    }

    @Test func readsFromACopyAndTellsTheProgramByTheFile() throws {
        let dir = try temporaryFolder("libs")
        let nml = dir.appendingPathComponent("collection.nml")
        try Data("<NML><COLLECTION></COLLECTION></NML>".utf8).write(to: nml)
        let before = try FileManager.default.attributesOfItem(atPath: nml.path)[.modificationDate] as? Date
        let lib = try DJLibrary.read(.traktor, at: nml)
        #expect(lib.entries.isEmpty && lib.written == before && lib.file == nml.path)
        #expect(try FileManager.default.attributesOfItem(atPath: nml.path)[.modificationDate] as? Date == before)
        #expect(DJProgram.of(file: nml) == .traktor)
        let vdj = dir.appendingPathComponent("database.xml")
        try Data("<?xml version=\"1.0\"?>\n<VirtualDJ_Database Version=\"8\"></VirtualDJ_Database>".utf8).write(to: vdj)
        #expect(DJProgram.of(file: vdj) == .virtualDJ)
        #expect(DJProgram.of(file: dir.appendingPathComponent("m.db")) == .engineDJ)
        #expect(DJProgram.of(file: dir.appendingPathComponent("notes.txt")) == nil)
    }

    @Test func standardLocationsOnAMacAndOnWindows() throws {
        let home = try temporaryFolder("home")
        let fm = FileManager.default
        for rel in ["Documents/Native Instruments/Traktor 3.11.1/collection.nml", "Documents/Native Instruments/Traktor 4.0.2/collection.nml",
                    "Music/_Serato_/database V2", "Music/Engine Library/Database2/m.db", "Documents/VirtualDJ/database.xml",
                    "AppData/Roaming/Pioneer/rekordbox/master.db"] {
            let u = home.appendingPathComponent(rel)
            try fm.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: u)
        }
        let found = DJLibraryLocations.inHome(home)
        #expect(found.map(\.program) == [.traktor, .traktor, .serato, .engineDJ, .virtualDJ])
        #expect(DJLibraryLocations.rekordboxDatabase(inHome: home))
        let stick = try temporaryFolder("stick")
        try fm.createDirectory(at: stick.appendingPathComponent("_Serato_"), withIntermediateDirectories: true)
        try Data().write(to: stick.appendingPathComponent("_Serato_/database V2"))
        #expect(DJLibraryLocations.onDrive(stick).map(\.program) == [.serato])
        #expect(!DJLibraryLocations.rekordboxExport(onDrive: stick))
    }

    @Test func pathKeys() {
        #expect(PathKey.key("C:\\Users\\DJ\\Music\\Café.mp3") == PathKey.key("/c:/users/dj/music/Cafe\u{301}.mp3"))
        #expect(PathKey.key("/Users/dj/Music/Engine Library/../House/a.mp3") == "/users/dj/music/house/a.mp3")
        #expect(PathKey.isAbsolute("C:/x") && PathKey.isAbsolute("/x") && !PathKey.isAbsolute("Music/x"))
    }
}

@Suite struct DJLibraryMatcherTests {
    static func lib(_ program: DJProgram, _ entries: [DJLibraryEntry], written: Double = 0) -> DJLibrary {
        DJLibrary(program: program, file: "/lib", written: Date(timeIntervalSince1970: written), entries: entries)
    }

    @Test func byPathThenBySuffixThenByNameAndSize() {
        let m = DJLibraryMatcher([Self.lib(.traktor, [
            DJLibraryEntry(paths: ["C:/Music/House/a.mp3"], keyAsWritten: "Am", size: 100),
            DJLibraryEntry(paths: ["/Old/Mac/Set/b.mp3"], keyAsWritten: "C", size: 200),
            DJLibraryEntry(paths: ["/Elsewhere/c.mp3"], keyAsWritten: "Dm", size: 300),
            DJLibraryEntry(paths: ["/One/d.mp3"], keyAsWritten: "Em", size: 400),
            DJLibraryEntry(paths: ["/Two/d.mp3"], keyAsWritten: "Fm", size: 400),
        ])])
        // the same path, written by Windows
        #expect(m.match(paths: ["c:\\music\\house\\A.mp3"], rels: [], size: nil).first?.entry.camelot == "8A")
        // moved: the path below the folder read ends the library's path
        #expect(m.match(paths: ["/Volumes/Stick/Set/b.mp3"], rels: ["Set/b.mp3"], size: nil).first?.entry.camelot == "8B")
        // a file name alone is not enough without the size
        #expect(m.match(paths: ["/New/c.mp3"], rels: ["c.mp3"], size: nil).isEmpty)
        #expect(m.match(paths: ["/New/c.mp3"], rels: ["c.mp3"], size: 300).first?.entry.camelot == "7A")
        #expect(m.match(paths: ["/New/c.mp3"], rels: ["c.mp3"], size: 301).isEmpty)
        // two entries fit equally: none is taken
        #expect(m.match(paths: ["/New/d.mp3"], rels: ["d.mp3"], size: 400).isEmpty)
    }
}

@Suite struct LocalFactsApplyTests {
    static func track(_ id: String, title: String, family: String = "deckie", rel: String, track n: Int? = nil,
                      disc: String? = "Stick", key: CrateTrack.Key? = nil, source: String = "filename", cut: String? = nil) -> CrateTrack {
        CrateTrack(id: id, file: .init(name: CratePath.lastName(rel), rel: rel, bytes: 1000, sha1Head: nil, durationS: 200),
                   ident: .init(title: title, source: source, disc: disc, folder: CratePath.folder(of: rel), track: n, cutKey: cut),
                   analysis: .init(engine: "x", analysedAt: "2026-11-13T00:00:00Z", device: "Mac15,6", secs: 1, level: 1),
                   engine: .init(family: family, version: "0.4.0", platform: "macos-arm64", fidelity: 1, models: [], decoder: nil),
                   key: key, flags: key == nil ? [] : ["key_uncertain"])
    }
    static let engineKey = CrateTrack.Key(source: "hpcp-whitened", confidence: 0.3, camelot: "4A", key: "F", scale: "minor",
                                          votes: ["hpcp_edma": "4A"], changes: nil)

    static func id3(title: String? = nil, artist: String? = nil, key: String? = nil, comment: String? = nil) -> [UInt8] {
        var frames: [[UInt8]] = []
        if let title { frames.append(KeyTagTests.frame("TIT2", [3] + Array(title.utf8))) }
        if let artist { frames.append(KeyTagTests.frame("TPE1", [3] + Array(artist.utf8))) }
        if let key { frames.append(KeyTagTests.frame("TKEY", [0] + Array(key.utf8))) }
        if let comment { frames.append(KeyTagTests.frame("COMM", [0] + Array("eng".utf8) + [0] + Array(comment.utf8))) }
        return KeyTagTests.tag(frames) + FileTagsTests.mpegFrame
    }

    @Test func whichKeyWinsAndWhereItCameFrom() throws {
        let top = try temporaryFolder("stick-keys")
        let fm = FileManager.default
        try fm.createDirectory(at: top.appendingPathComponent("House"), withIntermediateDirectories: true)
        try Data(Self.id3(title: "Song A", artist: "Artist A", key: "Am")).write(to: top.appendingPathComponent("House/a.mp3"))
        try Data(Self.id3(title: "Song B", artist: "Artist B", comment: "6A - Energy 5")).write(to: top.appendingPathComponent("House/b.mp3"))
        try Data(Self.id3(title: "Song C", artist: "Artist C")).write(to: top.appendingPathComponent("House/c.mp3"))
        try Data(Self.id3(title: "Song D", artist: "Artist D", key: "C")).write(to: top.appendingPathComponent("House/d.mp3"))
        var c = Crate(manifest: CrateManifest(crateId: "c", name: "N", createdAt: "2026-11-13T00:00:00Z", devicesSeen: []), tracks: [
            Self.track("a", title: "x", rel: "House/a.mp3", key: Self.engineKey),
            Self.track("b", title: "x", rel: "House/b.mp3", key: Self.engineKey),
            Self.track("c", title: "x", rel: "House/c.mp3", key: Self.engineKey),
            Self.track("d", title: "x", family: "apple-mu", rel: "House/d.mp3", key: Self.engineKey),
        ])
        var files: [String: [LocalFacts.FileRef]] = [:]
        for t in c.tracks {
            files[t.id] = [.init(url: top.appendingPathComponent(t.file.rel!), rel: t.file.rel!, place: t.ident.ownPlace)]
        }
        let path = { (rel: String) in PathKey.slashes(top.appendingPathComponent(rel).path) }
        let traktor = DJLibraryMatcherTests.lib(.traktor, [DJLibraryEntry(paths: [path("House/a.mp3")], keyAsWritten: "9A")], written: 2000)
        let serato = DJLibraryMatcherTests.lib(.serato, [DJLibraryEntry(paths: [path("House/a.mp3")], keyAsWritten: "Em")], written: 1000)
        let report = LocalFacts.apply(to: &c, files: files, libraries: [serato, traktor])

        // a: Traktor (written last) wins over Serato and the tag; all three stay as votes; one of three agrees.
        let a = try #require(c.tracks[0].key)
        #expect(a.source == "traktor" && a.camelot == "9A" && a.key == "E" && a.scale == "minor")
        #expect(a.votes == ["traktor": "9A", "serato": "9A", "tag": "8A"])
        #expect(a.confidence == 0.667 && !c.tracks[0].flags.contains("key_uncertain"))
        // b: Mixed In Key's comment.
        #expect(c.tracks[1].key?.source == "tag-comment" && c.tracks[1].key?.camelot == "6A" && c.tracks[1].key?.confidence == 1)
        // c: nothing from the DJ, so Deckie's own reading stays out (D16): no key block, no key flag.
        #expect(c.tracks[2].key == nil && c.tracks[2].flags.isEmpty && !c.tracks[2].featuresPresent.contains("key"))
        // d: Apple's reading stays the key; the DJ's tag sits beside it.
        #expect(c.tracks[3].key?.camelot == "4A" && c.tracks[3].key?.source == "hpcp-whitened" && c.tracks[3].key?.votes["tag"] == "8B")
        #expect(report.keysFrom == ["traktor": 1, "tag-comment": 1, "apple-mu": 1] && report.keysNotRead == 1 && report.keysDisagree == 1)
        // The crate still holds together.
        _ = try CrateWriter.encode(c)
    }

    @Test func theNamingLadder() throws {
        let top = try temporaryFolder("stick-names")
        let fm = FileManager.default
        for f in ["Artist F - Album", "Mix", "Plain"] { try fm.createDirectory(at: top.appendingPathComponent(f), withIntermediateDirectories: true) }
        func write(_ rel: String, _ bytes: [UInt8] = FileTagsTests.mpegFrame) throws { try Data(bytes).write(to: top.appendingPathComponent(rel)) }
        try write("Plain/02 Song B.mp3")                              // the file name, its number its place
        try write("Plain/Artist C - Song C.mp3")                      // "Artist - Title"
        try write("Artist F - Album/01 Song F.mp3")                   // the folder as the artist
        try write("Mix/Track 01.wav")                                 // a cue sheet beside it
        try fm.createDirectory(at: top.appendingPathComponent("Mix"), withIntermediateDirectories: true)
        try Data("FILE \"Track 01.wav\" WAVE\n  TRACK 01 AUDIO\n    TITLE \"Cue Song\"\n    PERFORMER \"Cue Artist\"\n".utf8)
            .write(to: top.appendingPathComponent("Mix/list.cue"))
        try write("Plain/Track 07.mp3")                               // named only by a copy
        try write("Plain/Track 08.mp3")                               // named only by a DJ library
        try write("Plain/tagged.mp3", Self.id3(title: "8A - Tagged", artist: "Tagger"))  // tags, a key in the title
        try write("Plain/Track 09.mp3")                               // the DJ's own fix

        var c = Crate(manifest: CrateManifest(crateId: "c", name: "N", createdAt: "2026-11-13T00:00:00Z", devicesSeen: []), tracks: [
            Self.track("b", title: "x", rel: "Plain/02 Song B.mp3", track: 2),
            Self.track("c", title: "x", rel: "Plain/Artist C - Song C.mp3", track: 1),
            Self.track("f", title: "x", rel: "Artist F - Album/01 Song F.mp3", track: 1),
            Self.track("m", title: "x", rel: "Mix/Track 01.wav", track: 1),
            Self.track("p", title: "x", rel: "Plain/Track 07.mp3", track: 7, cut: "k1"),
            Self.track("q", title: "Song P", rel: "Elsewhere/p.mp3", track: 1, source: "tag", cut: "k1"),
            Self.track("r", title: "x", rel: "Plain/Track 08.mp3", track: 8),
            Self.track("t", title: "x", rel: "Plain/tagged.mp3", track: 9),
            Self.track("u", title: "My name", rel: "Plain/Track 09.mp3", track: 10, source: "user"),
        ])
        c.tracks[5].ident.artist = "Artist P"
        var files: [String: [LocalFacts.FileRef]] = [:]
        for t in c.tracks {
            files[t.id] = [.init(url: top.appendingPathComponent(t.file.rel!), rel: t.file.rel!, place: t.ident.ownPlace)]
        }
        let lib = DJLibraryMatcherTests.lib(.engineDJ, [DJLibraryEntry(paths: [PathKey.slashes(top.appendingPathComponent("Plain/Track 08.mp3").path)],
                                                                      title: "Engine Song", artist: "Engine Artist")])
        let report = LocalFacts.apply(to: &c, files: files, libraries: [lib])
        func ident(_ id: String) -> CrateTrack.Ident { c.tracks.first { $0.id == id }!.ident }
        #expect(ident("b").title == "Song B" && ident("b").artist == nil && ident("b").source == "filename")
        #expect(ident("c").title == "Song C" && ident("c").artist == "Artist C" && ident("c").source == "filename")
        #expect(ident("f").title == "Song F" && ident("f").artist == "Artist F" && ident("f").source == "filename+folder")
        #expect(ident("m").title == "Cue Song" && ident("m").artist == "Cue Artist" && ident("m").source == "cue")
        #expect(ident("p").title == "Song P" && ident("p").artist == "Artist P" && ident("p").source == "copy")
        #expect(ident("r").title == "Engine Song" && ident("r").artist == "Engine Artist" && ident("r").source == "engine-dj")
        #expect(ident("t").title == "Tagged" && ident("t").artist == "Tagger" && ident("t").source == "tag")
        #expect(ident("u").title == "My name" && ident("u").source == "user")
        #expect(c.tracks.first { $0.id == "t" }?.key?.source == "tag-title")
        // Still to name: b (no artist), and u (the DJ's own, with no artist).
        #expect(report.needName == 2)
        #expect(report.namesFrom["filename"] == 3 && report.namesFrom["folder"] == 1 && report.namesFrom["cue"] == 1
                && report.namesFrom["copy"] == 1 && report.namesFrom["engine-dj"] == 1)
    }
}

