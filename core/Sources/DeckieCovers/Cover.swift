import Foundation
import CStbImage
import DeckieCrate
#if canImport(ImageIO)
import ImageIO
import CoreGraphics
#endif

/// A song's cover for the crate file (D36; docs/architecture/crate-format.md, "Addition with D36"): the picture a
/// file carries, or the one beside it, made into one small JPEG that the crate file stores once for every song that
/// shares the picture.
///
/// The cover's name is the SHA-256 hash of the **source picture's bytes**, not of the thumbnail, so the same picture
/// gives the same name whichever system made the thumbnail, and songs of one release share one entry even if two
/// systems' thumbnails differ by a bit. On Linux and Windows the thumbnail is made by `CStbImage` (stb_image to
/// decode, whole-number area averaging to scale, stb_image_write to encode), which gives the same bytes on both. On
/// Apple's systems it is made by the system's own image code (ImageIO), whose bytes differ.
public struct Cover: Equatable, Sendable {
    /// The SHA-256 of the source picture, 64 lower-case hexadecimal characters: `file.cover`.
    public var hash: String
    /// The thumbnail, a JPEG.
    public var jpeg: Data
    /// The thumbnail's size in pixels.
    public var width: Int
    public var height: Int

    /// Why a picture did not become a cover.
    public enum Failure: Error, Equatable, Sendable {
        /// Not a JPEG or PNG that can be decoded: damaged, cut short, or another kind of picture.
        case unreadable
        /// More bytes or more pixels than a cover's source may have (`CrateFormat.coverMaxSourceBytes`, 8,192 a side).
        case tooLarge
        /// No thumbnail small enough could be made of it.
        case tooDetailed
    }

    /// The hash that names a picture's cover.
    public static func hash(of picture: Data) -> String { CrateIDs.sha256(of: picture) }

    /// The cover of `picture` (a JPEG's or a PNG's bytes).
    public static func make(_ picture: Data) throws(Failure) -> Cover {
        guard picture.count <= CrateFormat.coverMaxSourceBytes else { throw .tooLarge }
        // Quality steps down for the rare picture whose thumbnail is over the cap (dense noise).
        for quality in [CrateFormat.coverQuality, 60, 40] {
            let made = try thumbnail(picture, side: CrateFormat.coverSide, quality: quality)
            if made.jpeg.count <= CrateFormat.coverMaxBytes {
                return Cover(hash: hash(of: picture), jpeg: made.jpeg, width: made.width, height: made.height)
            }
        }
        throw .tooDetailed
    }

    static func thumbnail(_ picture: Data, side: Int, quality: Int) throws(Failure) -> (jpeg: Data, width: Int, height: Int) {
        #if canImport(ImageIO)
        return try systemThumbnail(picture, side: side, quality: quality)
        #else
        return try portableThumbnail(picture, side: side, quality: quality)
        #endif
    }

    /// The thumbnail by the vendored code: the same bytes on every system. What Linux and Windows use.
    public static func portableThumbnail(_ picture: Data, side: Int = CrateFormat.coverSide,
                                         quality: Int = CrateFormat.coverQuality) throws(Failure) -> (jpeg: Data, width: Int, height: Int) {
        var out: UnsafeMutablePointer<UInt8>? = nil
        var length = 0
        var w: Int32 = 0, h: Int32 = 0, sw: Int32 = 0, sh: Int32 = 0
        let code = picture.withUnsafeBytes { bytes in
            deckie_cover_thumbnail(bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, Int32(side), Int32(quality),
                                   &out, &length, &w, &h, &sw, &sh)
        }
        guard code == 0, let out else { throw code == 2 ? Failure.tooLarge : Failure.unreadable }
        defer { deckie_cover_free(out) }
        return (Data(bytes: out, count: length), Int(w), Int(h))
    }

    #if canImport(ImageIO)
    /// Whether a picture's last bytes are its format's own ending: a JPEG's end-of-image marker (allowing a little
    /// padding after it, which some writers leave) or a PNG's closing chunk. A file cut short has neither.
    static func endsAsItShould(_ picture: Data, kind: String?) -> Bool {
        let tail = Array(picture.suffix(4096))
        if kind == "public.png" {
            let end: [UInt8] = [0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82]
            return tail.count >= end.count && Array(tail.suffix(end.count)) == end
        }
        guard tail.count >= 2 else { return false }
        for i in stride(from: tail.count - 2, through: 0, by: -1) where tail[i] == 0xFF && tail[i + 1] == 0xD9 {
            return tail[(i + 2)...].allSatisfy { $0 == 0 || $0 == 0xFF }
        }
        return false
    }

    /// The thumbnail by Apple's ImageIO. Written for the Mac and the iPad and not compiled or run where this was
    /// written (Linux and Windows): to be checked on a Mac.
    static func systemThumbnail(_ picture: Data, side: Int, quality: Int) throws(Failure) -> (jpeg: Data, width: Int, height: Int) {
        guard let source = CGImageSourceCreateWithData(picture as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let sw = properties[kCGImagePropertyPixelWidth] as? Int, let sh = properties[kCGImagePropertyPixelHeight] as? Int
        else { throw .unreadable }
        guard sw <= 8192, sh <= 8192 else { throw .tooLarge }
        // The same pictures as on Linux and Windows, and no others: a JPEG or a PNG, whole. ImageIO reads many more
        // kinds and will make a thumbnail from the top half of a file that was cut short; a cover is refused then,
        // not guessed at (checked on a Mac, Nov 14, 2026).
        let kind = CGImageSourceGetType(source) as String?
        guard kind == "public.jpeg" || kind == "public.png" else { throw .unreadable }
        guard CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else { throw .unreadable }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: min(side, max(sw, sh)),
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw .unreadable }
        // Only decoding shows that a file was cut short: asked again afterwards, ImageIO says so.
        guard CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete,
              Self.endsAsItShould(picture, kind: kind) else { throw .unreadable }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { throw .unreadable }
        // Anything see-through is laid over white by drawing into a context without alpha first.
        var opaque = image
        if let space = CGColorSpace(name: CGColorSpace.sRGB),
           let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                   space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) {
            context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            if let flat = context.makeImage() { opaque = flat }
        }
        CGImageDestinationAddImage(destination, opaque, [kCGImageDestinationLossyCompressionQuality: Double(quality) / 100] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw .unreadable }
        return (data as Data, opaque.width, opaque.height)
    }
    #endif

    /// Writes the cover's thumbnail into the crate file's package at `package` (`covers/<hash>.jpg`), unless it is
    /// there already.
    public func write(into package: URL) throws {
        let url = package.appendingPathComponent(CrateFormat.coversFolder).appendingPathComponent(hash + ".jpg")
        if FileManager.default.fileExists(atPath: url.path) { return }
        try DeckieFiles.createDirectory(url.deletingLastPathComponent())
        try DeckieFiles.write(jpeg, to: url)
    }
}
