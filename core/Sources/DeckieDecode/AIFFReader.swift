import Foundation

/// AIFF and AIFF-C (Apple's Audio Interchange File Format and its compressed variant) in plain Swift, the WAV
/// reader's big-endian sibling. The file is "FORM", a 32-bit size, "AIFF" or "AIFC", then chunks: a four-letter id,
/// a 32-bit size, the body, a pad byte if the size is odd. Every number is big-endian. Two chunks matter, wherever
/// they sit; the others (FVER, MARK, INST, COMT, NAME, ANNO, APPL, "ID3 " and so on) are skipped. Offsets in bytes
/// from the start of each body:
///
///     COMM   0-1    channels
///            2-5    sample frames (not used: the length comes from SSND, as in libsndfile)
///            6-7    bits per sample
///            8-17   sample rate, an 80-bit extended float (`extended80`)
///            18-21  AIFF-C only: compression type, then its name as a Pascal string (not used)
///     SSND   0-3    offset: bytes to skip before the first sample (usually 0)
///            4-7    block size, for aligned writing (not used)
///            8-     the samples, interleaved, from the offset on
///
/// Samples are two's-complement integers (8-bit ones too, unlike WAV's), each in the fewest whole bytes that hold
/// it, left-justified: big-endian in AIFF and in AIFF-C "NONE", little-endian in AIFF-C "sowt" (what macOS writes).
/// AIFF-C "fl32" or "FL32" is 32-bit big-endian float, whatever the bits field says. Integers are divided by
/// 2^(8 × bytes - 1), so 16-bit by 2^15 as in the WAV reader, and 12- or 20-bit samples, left-justified in 2 or 3
/// bytes, come out the same way as in libsndfile. Every other compression type ("twos", "ima4", "ulaw", "alaw",
/// "fl64" and so on) is reported as not supported, by name.
///
/// Where a file and its COMM chunk disagree this follows the lab's decoder, libsndfile 1.2.2 (soundfile 0.14.0),
/// as measured on Oct 28, 2026: the number of frames is what the SSND chunk holds, whatever COMM says (a partial
/// last frame is dropped); an SSND chunk running past the end of the file, or with size 0 (what a writer that
/// cannot go back leaves, such as ffmpeg writing to a pipe), is read to the end of the file; a sample rate with a
/// fraction (early Macs recorded at 22,254.545 Hz) keeps its whole part. Mono stays mono; more than two channels
/// are cut to the first two.
enum AIFFReader {
    static func decode(_ data: Data, file: String) throws(AudioDecodeError) -> AudioBuffer {
        let result: Result<AudioBuffer, AudioDecodeError> = data.withUnsafeBytes { raw in
            do throws(AudioDecodeError) {
                return .success(try parse(raw, file: file))
            } catch {
                return .failure(error)
            }
        }
        return try result.get()
    }

    /// An 80-bit IEEE 754 extended-precision number, the format of the 68881 and x87 floating-point units, in
    /// which AIFF stores the sample rate. Ten bytes, big-endian:
    ///
    ///     byte 0, top bit   sign
    ///     the next 15 bits  exponent, biased by 16,383
    ///     bytes 2-9         64-bit significand with its integer bit written out (bit 63; 1 in every normal
    ///                       number), so the binary point sits after bit 63
    ///
    /// value = (-1)^sign × significand × 2^(exponent - 16,383 - 63). Exponent 0x7FFF is infinity (significand 0
    /// apart from the integer bit) or NaN. 44,100 Hz, 0xAC44 × 2^0, is 40 0E AC 44 00 00 00 00 00 00: exponent
    /// 0x400E = 16,383 + 15, significand 0xAC44 shifted up 48 bits.
    ///
    /// Exact whenever the significand fits a Double's 53 bits, as every whole number below 2^53 does; otherwise
    /// rounded to the nearest Double.
    static func extended80(_ b: [UInt8]) -> Double {
        precondition(b.count == 10)
        let negative = b[0] & 0x80 != 0
        let exponent = Int(b[0] & 0x7F) << 8 | Int(b[1])
        let significand = b[2..<10].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
        let sign: FloatingPointSign = negative ? .minus : .plus
        if exponent == 0x7FFF {
            return significand << 1 == 0 ? (negative ? -.infinity : .infinity) : .nan
        }
        if significand == 0 { return negative ? -0.0 : 0 }
        // Double(significand) is the only step that can round; scaling by a power of two is exact.
        return Double(sign: sign, exponent: exponent - 16383 - 63, significand: Double(significand))
    }

    /// Integers in 1 to 4 whole bytes, in either byte order, or 32-bit big-endian float.
    private enum Encoding { case bigEndian(Int), littleEndian(Int), float32 }

    private static func parse(_ raw: UnsafeRawBufferPointer, file: String) throws(AudioDecodeError) -> AudioBuffer {
        func damaged(_ m: String) -> AudioDecodeError { .init(kind: .damaged, file: file, format: .aiff, message: m) }
        func unsupported(_ m: String) -> AudioDecodeError { .init(kind: .unsupported, file: file, format: .aiff, message: m) }
        func u32(_ o: Int) -> Int { Int(UInt32(bigEndian: raw.loadUnaligned(fromByteOffset: o, as: UInt32.self))) }
        func i16(_ o: Int) -> Int { Int(Int16(bigEndian: raw.loadUnaligned(fromByteOffset: o, as: Int16.self))) }
        func fourCC(_ o: Int) -> String { String(decoding: raw[o..<(o + 4)], as: UTF8.self) }

        guard raw.count >= 12 else { throw damaged("the file ends inside its FORM header") }
        let aifc = fourCC(8) == "AIFC"  // AudioFormat.sniff has checked "FORM" and "AIFF" or "AIFC"
        var comm: (channels: Int, bits: Int, rate: Double, compression: String)? = nil
        var sound: Range<Int>? = nil
        var o = 12
        while o + 8 <= raw.count {
            let id = fourCC(o)
            var size = u32(o + 4)
            let start = o + 8
            // A chunk running past the end of the file (one still being written, or cut short) is read as far as
            // it goes; an SSND chunk of size 0 runs to the end (see the type's comment).
            if id == "SSND" && size == 0 { size = raw.count - start }
            let end = min(start + size, raw.count)
            if id == "COMM" {
                guard end - start >= 18 else { throw damaged("the COMM chunk is too short") }
                guard !aifc || end - start >= 22 else { throw damaged("the AIFF-C COMM chunk has no compression type") }
                comm = (i16(start), i16(start + 6), extended80(Array(raw[(start + 8)..<(start + 18)])),
                        aifc ? fourCC(start + 18) : "NONE")
            } else if id == "SSND" {
                guard end - start >= 8 else { throw damaged("the SSND chunk is too short") }
                let first = start + 8 + u32(start)
                guard first <= end else { throw damaged("the SSND chunk's offset points past its end") }
                sound = first..<end
            }
            o = start + size + (size & 1)
        }
        guard let c = comm else { throw damaged("no COMM chunk") }
        guard let d = sound else { throw damaged("no SSND chunk") }
        guard c.channels > 0 else { throw damaged("the COMM chunk gives no channels") }
        // Whole hertz, the fraction dropped, as libsndfile does. Anything below 1 Hz, or not a number, is damage.
        guard c.rate >= 1 && c.rate < 0x1p32 else {
            throw damaged("the COMM chunk gives no usable sample rate (\(c.rate))")
        }
        let rate = Int(c.rate)

        let encoding: Encoding
        switch c.compression {
        case "NONE", "sowt":
            guard c.bits > 0 else { throw damaged("the COMM chunk gives no sample size") }
            guard c.bits <= 32 else { throw unsupported("\(c.bits)-bit integer PCM is not supported (up to 32 bits is)") }
            let bytes = (c.bits + 7) / 8
            encoding = c.compression == "NONE" ? .bigEndian(bytes) : .littleEndian(bytes)
        case "fl32", "FL32":
            encoding = .float32
        default:
            throw unsupported("AIFF-C compression type '\(c.compression)' is not supported (NONE, sowt and fl32 are)")
        }

        let width: Int
        let convert: (Int) -> Float
        switch encoding {
        case .bigEndian(1), .littleEndian(1):
            width = 1
            convert = { Float(Int8(bitPattern: raw[$0])) * 0x1p-7 }
        case .bigEndian(2):
            width = 2
            convert = { Float(Int16(bigEndian: raw.loadUnaligned(fromByteOffset: $0, as: Int16.self))) * 0x1p-15 }
        case .littleEndian(2):
            width = 2
            convert = { Float(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: $0, as: Int16.self))) * 0x1p-15 }
        case .bigEndian(3):
            width = 3
            convert = { o in
                let v = Int32(Int8(bitPattern: raw[o])) << 16 | Int32(raw[o + 1]) << 8 | Int32(raw[o + 2])
                return Float(v) * 0x1p-23
            }
        case .littleEndian(3):
            width = 3
            convert = { o in
                let v = Int32(raw[o]) | Int32(raw[o + 1]) << 8 | Int32(Int8(bitPattern: raw[o + 2])) << 16
                return Float(v) * 0x1p-23
            }
        case .bigEndian:  // 4 bytes
            width = 4
            convert = { Float(Int32(bigEndian: raw.loadUnaligned(fromByteOffset: $0, as: Int32.self))) * 0x1p-31 }
        case .littleEndian:  // 4 bytes
            width = 4
            convert = { Float(Int32(littleEndian: raw.loadUnaligned(fromByteOffset: $0, as: Int32.self))) * 0x1p-31 }
        case .float32:
            width = 4
            convert = { Float(bitPattern: UInt32(bigEndian: raw.loadUnaligned(fromByteOffset: $0, as: UInt32.self))) }
        }

        let blockAlign = c.channels * width
        let frames = d.count / blockAlign  // a partial last frame is dropped
        let channels = min(c.channels, 2)
        let samples = [Float](unsafeUninitializedCapacity: frames * channels) { buf, count in
            for i in 0..<frames {
                let at = d.lowerBound + i * blockAlign
                for ch in 0..<channels { buf[i * channels + ch] = convert(at + ch * width) }
            }
            count = frames * channels
        }
        return AudioBuffer(sampleRate: rate, channelCount: channels, samples: samples)
    }
}
