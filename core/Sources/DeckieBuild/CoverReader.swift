import Foundation
import DeckieCrate

/// The picture a song's file carries, read for its cover (D36; docs/architecture/crate-format.md, "Addition with
/// D36"): the bytes exactly as they are in the file, a JPEG or a PNG as the tagger put them there. Nothing is decoded
/// here: `Cover.make` does that, and its name for the cover is the hash of these bytes, so they must not be changed.
///
/// Read from the same places the tag readers know (`FileFacts`, which goes on counting each picture as left out of
/// the text tags):
///
/// - **ID3v2** `APIC` (versions 2.3 and 2.4) and `PIC` (2.2), at the start of an MP3 or FLAC file or in a WAV or AIFF
///   file's `id3 ` chunk, with unsynchronisation undone as the tag reader undoes it;
/// - **FLAC** `PICTURE` blocks, and the same block in base64 in a Vorbis comment (`METADATA_BLOCK_PICTURE`), and the
///   older `COVERART` comment (the picture alone in base64);
/// - **MP4** `covr`.
///
/// A file may carry several pictures (the front, the back, the disc). The one typed "front cover" (type 3 in ID3 and
/// FLAC) is taken; when none says it is the front, the first picture is, which is what players show.
public enum CoverReader {
    /// What a file gave.
    public enum Found: Equatable, Sendable {
        /// No picture.
        case none
        /// The picture's bytes, as they are in the file.
        case picture(Data)
        /// A picture of more bytes than a cover's source may have (`CrateFormat.coverMaxSourceBytes`): not read.
        case tooLarge
    }

    /// ID3's and FLAC's picture type for the front cover.
    static let frontCover = 3

    /// The picture in the tags of the file at `url`; `.none` when it has none or cannot be read.
    public static func embedded(in url: URL) -> Found {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return .none }
        defer { try? handle.close() }
        let file = TagFile(handle: handle)
        guard let head = file.read(at: 0, count: 12), head.count >= 12 else { return .none }
        let b = [UInt8](head)
        func ascii(_ at: Int, _ s: String) -> Bool { Array(b[at..<(at + s.utf8.count)]) == Array(s.utf8) }
        var pictures = Pictures()
        if ascii(0, "RIFF") && ascii(8, "WAVE") {
            if let tag = riffID3(file, bigEndian: false) { id3(tag, into: &pictures) }
        } else if ascii(0, "FORM") && (ascii(8, "AIFF") || ascii(8, "AIFC")) {
            if let tag = riffID3(file, bigEndian: true) { id3(tag, into: &pictures) }
        } else if ascii(4, "ftyp") {
            mp4(file, into: &pictures)
        } else {
            var offset = 0
            if ascii(0, "ID3"), let size = ID3.tagSize(b) {
                if let tag = file.read(at: 0, count: size) { id3(tag, into: &pictures) }
                offset = size
            }
            if let marker = file.read(at: offset, count: 4), marker.elementsEqual("fLaC".utf8) {
                flac(file, at: offset + 4, into: &pictures)
            }
        }
        return pictures.chosen
    }

    /// The pictures found so far: only the one that would be chosen is kept, so a file with many large pictures
    /// holds one of them in memory.
    struct Pictures {
        private var best: (front: Bool, found: Found)?

        /// Whether a picture of this type would replace what is held (so its bytes are worth reading).
        func wants(type: Int) -> Bool {
            guard let best else { return true }
            return !best.front && type == CoverReader.frontCover
        }

        mutating func add(type: Int, _ bytes: @autoclosure () -> [UInt8], count: Int) {
            guard wants(type: type), count > 0 else { return }
            let found: Found = count > CrateFormat.coverMaxSourceBytes ? .tooLarge : .picture(Data(bytes()))
            best = (type == CoverReader.frontCover, found)
        }

        var chosen: Found { best?.found ?? .none }
    }

    // MARK: ID3v2

    /// The `APIC` and `PIC` frames of a whole ID3v2 tag (header included). The walk over the frames is the tag
    /// reader's (`FileFacts.id3`): the footer, the extended header, unsynchronisation of the whole tag (2.2, 2.3) or
    /// of one frame (2.4), a frame's group byte and data length; a compressed or encrypted frame is not read.
    static func id3(_ tag: Data, into pictures: inout Pictures) {
        let all = [UInt8](tag)
        guard let size = ID3.tagSize(all), all.count >= 10 else { return }
        let version = all[3], flags = all[5]
        var body = Array(all[10..<min(size, all.count)])
        if version == 4 && flags & 0x10 != 0 && body.count >= 10 { body.removeLast(10) }
        if version < 4 && flags & 0x80 != 0 { body = ID3.resynchronised(body) }
        var r = ByteCursor(Data(body))
        if version >= 3 && flags & 0x40 != 0 {
            guard let e = r.take(4) else { return }
            let n = version == 4 ? ID3.synchsafe(e[0], e[1], e[2], e[3]) - 4
                : Int(e[0]) << 24 | Int(e[1]) << 16 | Int(e[2]) << 8 | Int(e[3])
            guard n >= 0, r.skip(n) else { return }
        }
        while r.remaining > 0 {
            let idLength = version == 2 ? 3 : 4
            guard let head = r.take(version == 2 ? 6 : 10), head[0] != 0 else { break }
            let id = String(decoding: head[0..<idLength], as: UTF8.self)
            guard id.allSatisfy({ $0.isASCII && ($0.isUppercase || $0.isNumber) }) else { break }
            let size: Int
            switch version {
            case 2: size = Int(head[3]) << 16 | Int(head[4]) << 8 | Int(head[5])
            case 3: size = Int(head[4]) << 24 | Int(head[5]) << 16 | Int(head[6]) << 8 | Int(head[7])
            default: size = ID3.synchsafe(head[4], head[5], head[6], head[7])
            }
            guard size >= 0 else { break }
            guard id == (version == 2 ? "PIC" : "APIC") else {
                guard r.skip(size) else { break }
                continue
            }
            guard var data = r.take(size) else { break }
            if version >= 3 {
                let format = head[9]
                if version == 3 {
                    if format & 0xC0 != 0 { continue }  // compressed or encrypted
                    if format & 0x20 != 0 { data = Array(data.dropFirst()) }
                } else {
                    if format & 0x0C != 0 { continue }
                    if format & 0x40 != 0 { data = Array(data.dropFirst()) }
                    if format & 0x02 != 0 || flags & 0x80 != 0 { data = ID3.resynchronised(data) }
                    if format & 0x01 != 0 { data = Array(data.dropFirst(4)) }
                }
            }
            if let (type, picture) = pictureFrame(data, version: version) {
                pictures.add(type: type, Array(picture), count: picture.count)
            }
        }
    }

    /// One picture frame's type and picture. `APIC`: the text encoding of the description, the picture's kind as a
    /// MIME type (Latin-1, ended by a NUL), the picture type, a description in that encoding (ended by one NUL, or
    /// two in UTF-16), then the picture. `PIC` (2.2) has three letters ("JPG", "PNG") in place of the MIME type. A
    /// frame whose kind is `-->` holds a link to a picture, not a picture, and gives nothing.
    static func pictureFrame(_ data: [UInt8], version: UInt8) -> (type: Int, picture: ArraySlice<UInt8>)? {
        guard let encoding = data.first else { return nil }
        var at = 1
        if version == 2 {
            guard data.count >= at + 3 else { return nil }
            if data[at..<(at + 3)].elementsEqual("-->".utf8) { return nil }
            at += 3
        } else {
            guard let end = data[at...].firstIndex(of: 0) else { return nil }
            if data[at..<end].elementsEqual("-->".utf8) { return nil }
            at = end + 1
        }
        guard at < data.count else { return nil }
        let type = Int(data[at])
        at += 1
        // The description is not needed, only where it ends: UTF-16 (encodings 1 and 2) ends at two NULs on an even
        // step, Latin-1 and UTF-8 at one.
        let wide = encoding == 1 || encoding == 2
        var end: Int? = nil
        var i = at
        while i < data.count {
            if wide {
                if i + 1 < data.count && data[i] == 0 && data[i + 1] == 0 { end = i + 2; break }
                i += 2
            } else {
                if data[i] == 0 { end = i + 1; break }
                i += 1
            }
        }
        guard let end, end < data.count else { return nil }
        return (type, startingAtThePicture(data[end...]))
    }

    /// Some taggers end a description with one NUL too few or too many, which leaves a stray byte or two before the
    /// picture. When the bytes do not start as a JPEG or a PNG does but one starts within the next few, the picture
    /// is taken from there; otherwise the bytes stay as they are (and `Cover.make` says whether they are a picture).
    static func startingAtThePicture(_ bytes: ArraySlice<UInt8>) -> ArraySlice<UInt8> {
        let jpeg: [UInt8] = [0xFF, 0xD8, 0xFF], png: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        for skip in 0..<min(8, max(0, bytes.count - 4)) {
            let from = bytes.startIndex + skip
            if bytes[from...].starts(with: jpeg) || bytes[from...].starts(with: png) { return bytes[from...] }
        }
        return bytes
    }

    /// The ID3v2 tag in a WAV (`id3 ` or `ID3 ` chunk, little-endian sizes) or AIFF (`ID3 `, big-endian) file.
    static func riffID3(_ file: TagFile, bigEndian: Bool) -> Data? {
        var at = 12
        for _ in 0..<64 {
            guard let h = file.read(at: at, count: 8), h.count == 8 else { break }
            let b = [UInt8](h)
            let id = String(decoding: b[0..<4], as: UTF8.self)
            let size = bigEndian
                ? Int(b[4]) << 24 | Int(b[5]) << 16 | Int(b[6]) << 8 | Int(b[7])
                : Int(b[7]) << 24 | Int(b[6]) << 16 | Int(b[5]) << 8 | Int(b[4])
            if id == "id3 " || id == "ID3 " {
                return size <= ID3.maxTagBytes ? file.read(at: at + 8, count: size) : nil
            }
            at += 8 + size + (size & 1)
        }
        return nil
    }

    // MARK: FLAC

    /// A FLAC file's metadata blocks from `start`: each `PICTURE` block (type 6), and the pictures a Vorbis comment
    /// block (type 4) carries in base64.
    static func flac(_ file: TagFile, at start: Int, into pictures: inout Pictures) {
        var at = start
        for _ in 0..<128 {
            guard let h = file.read(at: at, count: 4), h.count == 4 else { break }
            let b = [UInt8](h)
            let last = b[0] & 0x80 != 0, type = b[0] & 0x7F
            let size = Int(b[1]) << 16 | Int(b[2]) << 8 | Int(b[3])
            if type == 6 {
                // The picture type is the block's first four bytes: a block that would not be chosen is not read.
                if let t = file.read(at: at + 4, count: 4), pictures.wants(type: Int(be32([UInt8](t), 0))),
                   let block = file.read(at: at + 4, count: size) {
                    pictureBlock([UInt8](block), into: &pictures)
                }
            } else if type == 4, let block = file.read(at: at + 4, count: size) {
                vorbis(block, into: &pictures)
            }
            if last { break }
            at += 4 + size
        }
    }

    static func be32(_ b: [UInt8], _ at: Int) -> Int {
        Int(b[at]) << 24 | Int(b[at + 1]) << 16 | Int(b[at + 2]) << 8 | Int(b[at + 3])
    }

    /// A FLAC picture block: the picture type, the kind as a MIME type and a description (each a 32-bit big-endian
    /// length, then the text), the width, height, colour depth and colour count (four numbers), then the picture's
    /// length and the picture.
    static func pictureBlock(_ b: [UInt8], into pictures: inout Pictures) {
        var at = 0
        func number() -> Int? {
            guard at + 4 <= b.count else { return nil }
            defer { at += 4 }
            return be32(b, at)
        }
        guard let type = number(), let mime = number(), at + mime <= b.count else { return }
        if b[at..<(at + mime)].elementsEqual("-->".utf8) { return }
        at += mime
        guard let description = number(), at + description + 16 <= b.count else { return }
        at += description + 16
        guard let length = number(), length > 0, at + length <= b.count else { return }
        pictures.add(type: type, Array(b[at..<(at + length)]), count: length)
    }

    /// The pictures in a Vorbis comment block: `METADATA_BLOCK_PICTURE` (a FLAC picture block in base64) and the
    /// older `COVERART` (the picture alone in base64, with no type: taken as any other picture).
    static func vorbis(_ block: Data, into pictures: inout Pictures) {
        var r = ByteCursor(block)
        guard let vendor = r.u32le(), r.skip(Int(vendor)), let count = r.u32le() else { return }
        for _ in 0..<min(Int(count), 10_000) {
            guard let n = r.u32le(), let bytes = r.take(Int(n)) else { break }
            guard let eq = bytes.firstIndex(of: 0x3D) else { continue }
            let key = String(decoding: bytes[..<eq], as: UTF8.self).uppercased()
            guard key == "METADATA_BLOCK_PICTURE" || key == "COVERART" else { continue }
            guard let decoded = Data(base64Encoded: Data(bytes[(eq + 1)...]), options: .ignoreUnknownCharacters) else { continue }
            if key == "COVERART" { pictures.add(type: 0, [UInt8](decoded), count: decoded.count) }
            else { pictureBlock([UInt8](decoded), into: &pictures) }
        }
    }

    // MARK: MP4

    /// An MP4's `covr`: its first `data` box is the picture (kind 13 a JPEG, 14 a PNG; some taggers write 0). MP4
    /// has no picture types, so the first is the cover, as players take it.
    static func mp4(_ file: TagFile, into pictures: inout Pictures) {
        guard let (m, ilst) = FileFacts.mp4Items(file) else { return }
        for (type, body) in FileFacts.boxes(m, ilst) where type == "covr" {
            for (t, r) in FileFacts.boxes(m, body) where t == "data" && r.count > 8 {
                let picture = m[(r.lowerBound + 8)..<r.upperBound]
                pictures.add(type: 0, Array(picture), count: picture.count)
            }
        }
    }
}

/// A picture beside the music: used for a song whose file carries no picture of its own.
///
/// In the song's own folder, a file named `cover`, `folder`, `front`, `albumart` or `album`, with the extension
/// `.jpg`, `.jpeg` or `.png`, whatever its upper and lower case; the names are tried in that order, and for each name
/// the extensions in that order. Why these: `folder.jpg` is what Windows Media Player and Windows Explorer write and
/// read for a folder of music (Windows marks it hidden, which does not matter here: it is asked for by name);
/// `cover.jpg` and `front.jpg` are what CD rippers and download stores write beside an album's files; `albumart` and
/// `album` are the names other players and taggers use for the same thing.
///
/// The known weakness: the picture is the folder's, not the song's. A folder of unrelated singles that happens to
/// hold one such picture gives every song in it that picture (every song, that is, whose file carries none of its
/// own). A picture in the file always wins, and only the song's own folder is looked in, never the one above.
public enum CoverBeside {
    public static let names = ["cover", "folder", "front", "albumart", "album"]
    public static let extensions = ["jpg", "jpeg", "png"]

    /// The picture file of `folder`, by the names above; nil when it has none.
    public static func find(in folder: URL) -> URL? {
        guard let listed = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return nil }
        // By lower-case name; of two that differ only by case (possible off Windows), the first in byte order.
        var byName: [String: String] = [:]
        for name in listed.sorted(by: { $0.utf8.lexicographicallyPrecedes($1.utf8) }) {
            let lower = name.lowercased()
            if byName[lower] == nil { byName[lower] = name }
        }
        for name in names {
            for ext in extensions {
                guard let actual = byName["\(name).\(ext)"] else { continue }
                let url = folder.appendingPathComponent(actual)
                var isFolder: ObjCBool = false
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), !isFolder.boolValue { return url }
            }
        }
        return nil
    }

    /// The bytes of the picture file at `url`; `.tooLarge` (unread) over `CrateFormat.coverMaxSourceBytes`, `.none`
    /// when it is empty or cannot be read.
    public static func read(_ url: URL) -> CoverReader.Found {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber
        if let size, size.intValue > CrateFormat.coverMaxSourceBytes { return .tooLarge }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return .none }
        return data.count > CrateFormat.coverMaxSourceBytes ? .tooLarge : .picture(data)
    }
}
