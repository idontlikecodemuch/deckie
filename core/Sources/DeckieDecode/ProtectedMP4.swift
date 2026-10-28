import Foundation

/// Rights-protected (DRM) MP4 files, recognised from their bytes so the build summary can count them as "protected,
/// cannot be read" apart from files DeckieDecode cannot decode yet (the main session's decision P18). Nothing is
/// opened, decrypted or sent anywhere; the file's own boxes say it is locked.
///
/// Detected, in any MP4 or QuickTime file whatever its extension (.m4p is only a hint: an .m4p renamed .m4a is
/// still found, an unlocked file named .m4p still reads as AAC):
/// - FairPlay, Apple's protection: iTunes Store purchases from before 2009 and Apple Music downloads (.m4p, also
///   .m4v and .m4b). The major brand "M4P ", or an audio sample entry "drms" or a video one "drmi".
/// - Any other protection written the standard MP4 way (ISO/IEC 14496-12, "protected sample entries"): a "sinf"
///   box inside a sample entry, as in Common Encryption ("enca", "encv"), which streaming services' DASH and HLS
///   downloads use.
///
/// The sample entries are found by walking the box tree (moov, trak, mdia, minf, stbl, stsd), jumping over the
/// audio by its size, so a moov after the audio (as ffmpeg writes it) is found as well as one before it (as iTunes
/// writes it), and the letters "sinf" or "drms" in a title or in the audio count for nothing. The file is already
/// in memory, so the walk costs a few dozen box headers.
///
/// Not detected:
/// - Spotify, Tidal, Amazon Music and Deezer offline downloads: encrypted caches inside each app's private storage,
///   not files a user would hand to the builder. Copied out anyway, nothing in them reads as audio, so they come
///   out as unrecognised.
/// - Windows Media DRM (protected WMA from the 2000s stores and subscriptions) and other containers DeckieDecode
///   does not recognise yet: they come out as unrecognised, not as protected.
enum ProtectedMP4 {
    /// What marks the file as protected.
    enum Finding: Equatable {
        /// Apple's FairPlay: the brand or sample entry seen, such as `major brand "M4P "`.
        case fairPlay(String)
        /// Another scheme's "sinf" box, in the sample entry named.
        case encrypted(String)

        /// The error message: plain words first, then what was seen.
        var message: String {
            switch self {
            case .fairPlay(let seen):
                return "protected, cannot be read: an iTunes Store or Apple Music file locked to its Apple account "
                    + "(FairPlay; \(seen)); only Apple's own apps can play it"
            case .encrypted(let seen):
                return "protected, cannot be read: the audio is encrypted (\(seen)); only the store's or streaming "
                    + "service's own app can play it"
            }
        }
    }

    /// Why the MP4 in `data` is protected, or nil when nothing says so (or it is not an MP4).
    static func check(_ data: Data) -> Finding? {
        data.withUnsafeBytes { check($0) }
    }

    private static func check(_ b: UnsafeRawBufferPointer) -> Finding? {
        func u32(_ o: Int) -> Int { Int(UInt32(bigEndian: b.loadUnaligned(fromByteOffset: o, as: UInt32.self))) }
        func fourCC(_ o: Int) -> String { String(decoding: b[o..<(o + 4)], as: UTF8.self) }

        /// The boxes laid end to end in `range`: a 32-bit size (1: a 64-bit size follows the type; 0: to the end of
        /// the range), a four-letter type, the body. A box running past the range is cut to it.
        func boxes(_ range: Range<Int>) -> [(type: String, body: Range<Int>)] {
            var found: [(type: String, body: Range<Int>)] = []
            var o = range.lowerBound
            while o + 8 <= range.upperBound {
                var size = u32(o), header = 8
                if size == 1 {
                    guard o + 16 <= range.upperBound else { break }
                    size = Int(clamping: UInt64(bigEndian: b.loadUnaligned(fromByteOffset: o + 8, as: UInt64.self)))
                    header = 16
                } else if size == 0 {
                    size = range.upperBound - o
                }
                guard size >= header else { break }  // not a box: stop rather than guess
                let end = o + min(size, range.upperBound - o)
                found.append((fourCC(o + 4), (o + header)..<end))
                o = end
            }
            return found
        }

        /// The bodies of the boxes at `path` below `range`, every branch followed.
        func bodies(_ range: Range<Int>, _ path: ArraySlice<String>) -> [Range<Int>] {
            guard let first = path.first else { return [range] }
            return boxes(range).filter { $0.type == first }.flatMap { bodies($0.body, path.dropFirst()) }
        }

        guard b.count >= 12, fourCC(4) == "ftyp" else { return nil }
        let top = boxes(0..<b.count)
        if let ftyp = top.first, ftyp.body.count >= 4, fourCC(ftyp.body.lowerBound) == "M4P " {
            return .fairPlay("major brand \"M4P \"")
        }
        for stsd in bodies(0..<b.count, ["moov", "trak", "mdia", "minf", "stbl", "stsd"]) where stsd.count >= 8 {
            // The stsd body: a version and flags (4 bytes), the entry count (4), then the sample entries as boxes.
            for entry in boxes((stsd.lowerBound + 8)..<stsd.upperBound) {
                if entry.type == "drms" || entry.type == "drmi" { return .fairPlay("sample entry \"\(entry.type)\"") }
                // A sample entry's own fields come before its child boxes, and how many there are depends on the
                // entry's kind and version, so "sinf" is looked for at every offset, counting only where the 4
                // bytes before it give a size that ends inside the entry.
                let e = entry.body
                var p = e.lowerBound + 4
                while p + 4 <= e.upperBound {
                    if b[p] == 0x73, fourCC(p) == "sinf", u32(p - 4) >= 8, p - 4 + u32(p - 4) <= e.upperBound {
                        return .encrypted("a \"sinf\" box in sample entry \"\(entry.type)\"")
                    }
                    p += 1
                }
            }
        }
        return nil
    }
}
