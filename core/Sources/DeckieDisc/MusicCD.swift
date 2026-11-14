import Foundation
import CDiscDrive
import DeckieCrate
#if os(Windows)
import WinSDK
#endif

/// What the drive said about CD-Text (research AA, 2.3: "no names on this disc" can mean the drive, not the disc, so
/// Desk says which it knows).
public enum TextReading: Equatable, Sendable {
    /// The drive answered with text that names something.
    case names(CDText)
    /// The drive answered, and there is no name on the disc.
    case none
    /// The drive could not be asked, or refused: the disc may have names this drive does not pass on.
    case unknown(String)

    /// As a code for messages and storage: `names`, `none` or `drive`.
    public var code: String {
        switch self {
        case .names: return "names"
        case .none: return "none"
        case .unknown: return "drive"
        }
    }

    public var text: CDText? { if case let .names(t) = self { return t }; return nil }

    /// What a drive's bytes say: names, none (an answer with no packs, or packs with no title or performer), or
    /// unknown (packs, but none could be read, or none in characters Desk reads).
    public static func from(_ bytes: [UInt8]) -> TextReading {
        let t = CDText.decode(bytes)
        if t.hasNames { return .names(t) }
        if t.packsRead == 0 && t.packsDamaged > 0 { return .unknown("every CD-Text pack the drive gave failed its check") }
        if let b = t.main, !b.characters.readable { return .unknown("the disc's text is in \(b.characters.rawValue), which Desk does not read yet") }
        return .none
    }
}

/// A music CD in a drive, however this computer reaches it.
public protocol MusicCD: AnyObject {
    /// Where it is, as Add music gives it back: a device ("/dev/sr0", "\\.\E:"), a mounted volume (the Mac), or a
    /// stand-in folder.
    var location: String { get }
    /// The file type its songs are copied as: "wav", or "aiff" on the Mac (the system's own files).
    var fileExtension: String { get }
    func tableOfContents() throws -> DiscTOC
    func readText() -> TextReading
    /// Copies one song into `url` (a new file); calls `progress(done, total)` in sectors. Returns the sectors that could
    /// not be read even on a second try (they are silence in the copy).
    func copy(_ song: DiscTOC.Song, to url: URL, progress: (Int, Int) -> Void) throws -> Int
}

/// The three things a drive is asked for, below everything that is the same on every computer: the table, the
/// CD-Text bytes, and sectors of sound. Linux and Windows reach a real drive through CDiscDrive; the stand-in reads
/// a folder made by a test.
public protocol SectorDevice: AnyObject {
    func tocBytes() throws -> (bytes: [UInt8], format: Int)
    func cdTextBytes() throws -> [UInt8]
    func audio(from lba: Int, sectors: Int) throws -> [UInt8]
}

/// A music CD read by sector (Linux, Windows, the stand-in): the table first, then CD-Text, then each song cut exactly
/// where the table says (letter AA, 2.6), with a second try on a part that fails, then one sector at a time; a sector
/// that fails both is silence in the copy, and counted.
public final class SectorMusicCD: MusicCD {
    public let location: String
    let device: SectorDevice
    public let fileExtension = "wav"
    /// Sectors asked for at once (20 sectors, 47 KB: under the 64 KB some drivers allow in one request).
    public static let chunk = 20

    public init(location: String, device: SectorDevice) { self.location = location; self.device = device }

    public func tableOfContents() throws -> DiscTOC {
        let (bytes, format) = try device.tocBytes()
        return format == 2 ? try DiscTOC.format2(bytes) : try DiscTOC.format0(bytes)
    }

    public func readText() -> TextReading {
        do { return TextReading.from(try device.cdTextBytes()) }
        catch { return .unknown("\(error)") }
    }

    public func copy(_ song: DiscTOC.Song, to url: URL, progress: (Int, Int) -> Void) throws -> Int {
        let part = url.appendingPathExtension("part")
        try DeckieFiles.remove(part)
        let handle = try DeckieFiles.openForAppending(part)
        var damaged = 0
        do {
            try handle.write(contentsOf: WAV.header(sectors: song.sectors))
            var lba = song.start
            while lba < song.end {
                let n = min(Self.chunk, song.end - lba)
                let bytes: [UInt8]
                if let b = try? device.audio(from: lba, sectors: n) { bytes = b }
                else if let b = try? device.audio(from: lba, sectors: n) { bytes = b }
                else {
                    var one: [UInt8] = []
                    for s in lba..<(lba + n) {
                        if let b = try? device.audio(from: s, sectors: 1) { one += b }
                        else { one += [UInt8](repeating: 0, count: DiscTOC.bytesPerSector); damaged += 1 }
                    }
                    bytes = one
                }
                try handle.write(contentsOf: Data(bytes))
                lba += n
                progress(lba - song.start, song.sectors)
            }
            try handle.close()
        } catch {
            try? handle.close()
            try? DeckieFiles.remove(part)
            throw error
        }
        try DeckieFiles.remove(url)
        try DeckieFiles.move(part, to: url)
        return damaged
    }
}

/// A canonical 44-byte WAV header for CD audio: 44,100 Hz, two channels, 16 bits.
public enum WAV {
    public static func header(sectors: Int) -> Data {
        let dataBytes = UInt32(sectors * DiscTOC.bytesPerSector)
        var d = Data()
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        d.append(contentsOf: Array("RIFF".utf8)); u32(36 + dataBytes)
        d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); u32(16); u16(1); u16(2); u32(44_100); u32(44_100 * 4); u16(4); u16(16)
        d.append(contentsOf: Array("data".utf8)); u32(dataBytes)
        return d
    }
}

/// A real drive through the system's own calls (CDiscDrive): Linux and Windows read the table, CD-Text and the sound;
/// the Mac only the table and CD-Text (its sound is read as files, `MacMusicCD`).
public final class SystemDrive: SectorDevice {
    let handle: cdd_handle
    public let path: String

    public init(path: String) throws {
        var h: cdd_handle = 0
        let r = cdd_open(path, &h)
        guard r == 0 else { throw DiscError("could not open the drive \(path) (system error \(r))") }
        handle = h
        self.path = path
    }

    deinit { cdd_close(handle) }

    public func tocBytes() throws -> (bytes: [UInt8], format: Int) {
        var buf = [UInt8](repeating: 0, count: 4 + 100 * 11)
        var length: Int32 = 0, format: Int32 = 0
        let r = cdd_read_toc(handle, &buf, Int32(buf.count), &length, &format)
        guard r == 0 else { throw DiscError("the drive \(path) did not give its table of contents (system error \(r))") }
        return (Array(buf.prefix(Int(length))), Int(format))
    }

    public func cdTextBytes() throws -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: 4 + 8 * 256 * 18)
        var length: Int32 = 0
        let r = cdd_read_cdtext(handle, &buf, Int32(buf.count), &length)
        guard r == 0 else { throw DiscError("the drive \(path) gave no CD-Text (system error \(r))") }
        return Array(buf.prefix(Int(length)))
    }

    public func audio(from lba: Int, sectors: Int) throws -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: sectors * DiscTOC.bytesPerSector)
        let r = cdd_read_audio(handle, Int32(lba), Int32(sectors), &buf)
        guard r == 0 else { throw DiscError("the drive \(path) could not read sectors \(lba) to \(lba + sectors - 1) (system error \(r))") }
        return buf
    }
}

/// The stand-in for a drive, for tests and for trying the flow with no drive: a folder holding what a drive would
/// answer, made from the format's description (never from a real disc):
///
///     toc.bin       the answer to "read table of contents", format 0, sector addresses
///     cdtext.bin    the answer in format 5 (header and packs); absent: the drive answered with no text;
///                   a file `cdtext.refused` instead: the drive refused
///     audio.pcm     the disc's sound from sector 0, 2352 bytes a sector
///     bad.txt       optional: sector numbers, one a line, that fail on the first try (to exercise the second try);
///                   a line "always N" fails every time
public final class StandInDrive: SectorDevice {
    public let folder: URL
    let pcm: FileHandle?
    var failedOnce = Set<Int>()
    let flaky: Set<Int>
    let broken: Set<Int>
    public private(set) var reads = 0

    public init(folder: URL) {
        self.folder = folder
        pcm = try? FileHandle(forReadingFrom: folder.appendingPathComponent("audio.pcm"))
        var f = Set<Int>(), b = Set<Int>()
        if let text = try? String(contentsOf: folder.appendingPathComponent("bad.txt"), encoding: .utf8) {
            for line in text.split(whereSeparator: \.isNewline) {
                let parts = line.split(separator: " ")
                if parts.count == 2, parts[0] == "always", let n = Int(parts[1]) { b.insert(n) }
                else if let n = Int(line.trimmingCharacters(in: .whitespaces)) { f.insert(n) }
            }
        }
        flaky = f; broken = b
    }

    deinit { try? pcm?.close() }

    public func tocBytes() throws -> (bytes: [UInt8], format: Int) {
        guard let d = try? Data(contentsOf: folder.appendingPathComponent("toc.bin")) else { throw DiscError("no disc in the stand-in drive") }
        return ([UInt8](d), 0)
    }

    public func cdTextBytes() throws -> [UInt8] {
        if FileManager.default.fileExists(atPath: folder.appendingPathComponent("cdtext.refused").path) {
            throw DiscError("the stand-in drive refused the CD-Text command")
        }
        guard let d = try? Data(contentsOf: folder.appendingPathComponent("cdtext.bin")) else { return [0, 2, 0, 0] }
        return [UInt8](d)
    }

    public func audio(from lba: Int, sectors: Int) throws -> [UInt8] {
        reads += 1
        for s in lba..<(lba + sectors) {
            if broken.contains(s) { throw DiscError("sector \(s) cannot be read") }
            if flaky.contains(s) && !failedOnce.contains(s) {
                failedOnce.insert(s)
                throw DiscError("sector \(s) failed once")
            }
        }
        guard let pcm else { throw DiscError("the stand-in drive has no sound") }
        try pcm.seek(toOffset: UInt64(lba * DiscTOC.bytesPerSector))
        let want = sectors * DiscTOC.bytesPerSector
        var out = [UInt8](try pcm.read(upToCount: want) ?? Data())
        if out.count < want { out += [UInt8](repeating: 0, count: want - out.count) }
        return out
    }
}

/// A music CD on the Mac: the system shows it as a volume (its file system is `cddafs`) holding one AIFF file a song,
/// "1 Audio Track.aiff" and so on, the sound read by the system. Desk copies those files. The table and CD-Text come
/// from the disc's raw device when the Mac lets Desk open it; when it does not, the table is made from the files'
/// lengths (the songs and their order are right; the gaps are not known) and the text is unknown.
public final class MacMusicCD: MusicCD {
    public let location: String
    public let fileExtension = "aiff"
    let volume: URL

    public init(volume: URL) {
        self.volume = volume
        location = volume.path
    }

    /// The songs' files, by number.
    public func files() -> [(number: Int, url: URL)] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: volume.path)) ?? []
        return names.compactMap { name -> (Int, URL)? in
            guard !name.hasPrefix("."), name.lowercased().hasSuffix(".aiff") || name.lowercased().hasSuffix(".aif"),
                  let n = Int(name.prefix { $0.isNumber }) else { return nil }
            return (n, volume.appendingPathComponent(name))
        }.sorted { $0.0 < $1.0 }
    }

    func rawDevice() -> SystemDrive? {
        var buf = [CChar](repeating: 0, count: 256)
        guard cdd_music_cd_device(volume.path, &buf, Int32(buf.count)) == 0 else { return nil }
        let path = String(decoding: buf.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return try? SystemDrive(path: path)
    }

    public func tableOfContents() throws -> DiscTOC {
        if let d = rawDevice(), let (bytes, format) = try? d.tocBytes(),
           let toc = try? (format == 2 ? DiscTOC.format2(bytes) : DiscTOC.format0(bytes)) {
            return toc
        }
        let f = files()
        guard !f.isEmpty else { throw DiscError("no songs on the music CD at \(volume.path)") }
        return DiscTOC.fromLengths(f.map { AIFF.frames(at: $0.url).map { ($0 + 587) / 588 } ?? 0 })
    }

    public func readText() -> TextReading {
        guard let d = rawDevice() else { return .unknown("this Mac did not let Desk open the disc's drive") }
        do { return TextReading.from(try d.cdTextBytes()) } catch { return .unknown("\(error)") }
    }

    public func copy(_ song: DiscTOC.Song, to url: URL, progress: (Int, Int) -> Void) throws -> Int {
        guard let file = files().first(where: { $0.number == song.number }) else {
            throw DiscError("song \(song.number) is not on the music CD at \(volume.path)")
        }
        let part = url.appendingPathExtension("part")
        try DeckieFiles.remove(part)
        try DeckieFiles.copy(file.url, to: part)
        try DeckieFiles.remove(url)
        try DeckieFiles.move(part, to: url)
        progress(song.sectors, song.sectors)
        return 0
    }
}

/// The frame count in an AIFF file's COMM chunk.
enum AIFF {
    static func frames(at url: URL) -> Int? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        guard let head = try? h.read(upToCount: 4096), head.count >= 12 else { return nil }
        let b = [UInt8](head)
        guard String(decoding: b[0..<4], as: UTF8.self) == "FORM" else { return nil }
        var i = 12
        while i + 8 <= b.count {
            let id = String(decoding: b[i..<(i + 4)], as: UTF8.self)
            let size = Int(b[i + 4]) << 24 | Int(b[i + 5]) << 16 | Int(b[i + 6]) << 8 | Int(b[i + 7])
            if id == "COMM", i + 14 <= b.count {
                return Int(b[i + 10]) << 24 | Int(b[i + 11]) << 16 | Int(b[i + 12]) << 8 | Int(b[i + 13])
            }
            i += 8 + size + (size & 1)
        }
        return nil
    }
}

/// The music CDs in this computer's drives, as Add music offers them beside drives and folders.
public enum MusicCDs {
    /// Read the folders inside this folder (or this folder, when it holds a `toc.bin`) as stand-in drives with a
    /// disc in each, in place of the real drives (tests, and trying the flow with no drive). D32's `DECKIE_DESK_DRIVES`
    /// does the same for drives.
    public static let standInVariable = "DECKIE_DESK_MUSIC_CD"

    public struct Found: Codable, Equatable, Sendable {
        /// Where it is (give it back to `open`).
        public var location: String
        /// What the system calls the drive: "E:", "/dev/sr0", the Mac's volume name, the stand-in's folder name.
        public var drive: String
        public var songs: Int
        public var seconds: Double
        public var discId: String
    }

    static func standIns(_ environment: [String: String]) -> [URL]? {
        guard let p = environment[standInVariable], !p.isEmpty else { return nil }
        let root = URL(fileURLWithPath: p, isDirectory: true)
        if FileManager.default.fileExists(atPath: root.appendingPathComponent("toc.bin").path) { return [root] }
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.filter { !$0.hasPrefix(".") }.sorted().map { root.appendingPathComponent($0, isDirectory: true) }
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("toc.bin").path) }
    }

    /// Opens the music CD at `location` (as `list` gave it).
    public static func open(_ location: String, environment: [String: String] = ProcessInfo.processInfo.environment) throws -> MusicCD {
        if let stands = standIns(environment) {
            guard let f = stands.first(where: { $0.standardizedFileURL.path == URL(fileURLWithPath: location).standardizedFileURL.path }) else {
                throw DiscError("no music CD at \(location)")
            }
            return SectorMusicCD(location: f.path, device: StandInDrive(folder: f))
        }
        #if os(macOS)
        return MacMusicCD(volume: URL(fileURLWithPath: location, isDirectory: true))
        #else
        return SectorMusicCD(location: location, device: try SystemDrive(path: location))
        #endif
    }

    /// Every drive holding a music CD: one with at least one audio track.
    public static func list(environment: [String: String] = ProcessInfo.processInfo.environment) -> [Found] {
        var out: [Found] = []
        func add(_ location: String, _ drive: String) {
            guard let cd = try? open(location, environment: environment), let toc = try? cd.tableOfContents(),
                  !toc.songs.isEmpty else { return }
            out.append(Found(location: cd.location, drive: drive, songs: toc.songs.count, seconds: toc.audioSeconds, discId: toc.id))
        }
        if let stands = standIns(environment) {
            for f in stands { add(f.path, f.lastPathComponent) }
            return out
        }
        #if os(macOS)
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: [.volumeNameKey], options: [.skipHiddenVolumes]) ?? []
        for u in urls where isMacMusicCD(u) {
            add(u.path, (try? u.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? u.lastPathComponent)
        }
        #elseif os(Windows)
        let mask = GetLogicalDrives()
        for i in 0..<26 where mask & (1 << UInt32(i)) != 0 {
            let letter = String(UnicodeScalar(UInt8(65 + i))) + ":"
            let type = (letter + "\\").withCString(encodedAs: UTF16.self) { GetDriveTypeW($0) }
            guard type == UINT(DRIVE_CDROM) else { continue }
            add("\\\\.\\" + letter, letter)
        }
        #else
        for n in 0..<16 {
            let p = "/dev/sr\(n)"
            if FileManager.default.fileExists(atPath: p) { add(p, p) }
        }
        #endif
        return out
    }

    /// Whether a mounted volume is a music CD (the Mac's cddafs), so the drives list leaves it to `list`.
    public static func isMacMusicCD(_ volume: URL) -> Bool {
        var buf = [CChar](repeating: 0, count: 256)
        return cdd_music_cd_device(volume.path, &buf, Int32(buf.count)) == 0
    }

    /// Whether a Windows drive's top holds a music CD (the system shows its songs as `Track01.cda` stubs), so the
    /// drives list leaves it to `list`.
    public static func isCDAudioRoot(_ root: URL) -> Bool {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        return names.contains { $0.lowercased().hasSuffix(".cda") }
    }
}
