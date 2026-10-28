import Foundation

/// RIFF/WAVE in plain Swift: 16-, 24- and 32-bit integer PCM and 32-bit float, plain or WAVE_FORMAT_EXTENSIBLE,
/// mono, stereo or more (the first two channels are kept). Other chunks (LIST, fact, cue, bext and so on) are
/// skipped wherever they sit. Integers are divided by 2^15, 2^23 or 2^31, as libsndfile does, so the samples match
/// the lab's `soundfile.read(..., dtype="float32")`.
enum WAVReader {
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

    private enum Encoding { case int16, int24, int32, float32 }

    private static func parse(_ raw: UnsafeRawBufferPointer, file: String) throws(AudioDecodeError) -> AudioBuffer {
        func damaged(_ m: String) -> AudioDecodeError { .init(kind: .damaged, file: file, format: .wav, message: m) }
        func unsupported(_ m: String) -> AudioDecodeError { .init(kind: .unsupported, file: file, format: .wav, message: m) }
        func u16(_ o: Int) -> Int { Int(UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: o, as: UInt16.self))) }
        func u32(_ o: Int) -> Int { Int(UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: o, as: UInt32.self))) }

        // The chunks after "RIFF", size, "WAVE": a four-letter id, a 32-bit size, the body, a pad byte if odd.
        var fmt: (code: Int, channels: Int, rate: Int, blockAlign: Int, bits: Int)? = nil
        var body: Range<Int>? = nil
        var o = 12
        while o + 8 <= raw.count {
            let id = String(decoding: raw[o..<(o + 4)], as: UTF8.self)
            let size = u32(o + 4)
            let start = o + 8
            // A chunk running past the end of the file (one still being written, or cut short) is read as far as
            // it goes.
            let end = min(start + size, raw.count)
            if id == "fmt " {
                guard end - start >= 16 else { throw damaged("the fmt chunk is too short") }
                var code = u16(start)
                if code == 0xFFFE {  // WAVE_FORMAT_EXTENSIBLE: the real code starts a GUID ending in this suffix
                    let suffix: [UInt8] = [0x00, 0x00, 0x00, 0x00, 0x10, 0x00, 0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71]
                    guard end - start >= 40 else { throw damaged("the extensible fmt chunk is too short") }
                    code = Array(raw[(start + 26)..<(start + 40)]) == suffix ? u16(start + 24) : -1
                }
                fmt = (code, u16(start + 2), u32(start + 4), u16(start + 12), u16(start + 14))
            } else if id == "data" {
                body = start..<end
            }
            o = start + size + (size & 1)
        }
        guard let f = fmt else { throw damaged("no fmt chunk") }
        guard let d = body else { throw damaged("no data chunk") }
        guard f.channels > 0, f.rate > 0 else { throw damaged("the fmt chunk gives no channels or no sample rate") }

        let encoding: Encoding
        switch (f.code, f.bits) {
        case (1, 16): encoding = .int16
        case (1, 24): encoding = .int24
        case (1, 32): encoding = .int32
        case (3, 32): encoding = .float32
        case (1, _): throw unsupported("\(f.bits)-bit integer PCM is not supported yet (16, 24 and 32 are)")
        case (3, _): throw unsupported("\(f.bits)-bit float is not supported yet (32 is)")
        default: throw unsupported("encoding \(f.code) is not supported (integer PCM and float are)")
        }
        let width = f.bits / 8
        guard f.blockAlign == f.channels * width else {
            throw damaged("block size \(f.blockAlign) does not match \(f.channels) channels of \(f.bits) bits")
        }

        let convert: (Int) -> Float
        switch encoding {
        case .int16:
            convert = { Float(Int16(littleEndian: raw.loadUnaligned(fromByteOffset: $0, as: Int16.self))) * 0x1p-15 }
        case .int24:
            convert = { o in
                let v = Int32(raw[o]) | Int32(raw[o + 1]) << 8 | Int32(Int8(bitPattern: raw[o + 2])) << 16
                return Float(v) * 0x1p-23
            }
        case .int32:
            convert = { Float(Int32(littleEndian: raw.loadUnaligned(fromByteOffset: $0, as: Int32.self))) * 0x1p-31 }
        case .float32:
            convert = { Float(bitPattern: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: $0, as: UInt32.self))) }
        }

        let frames = d.count / f.blockAlign  // a partial last frame is dropped
        let channels = min(f.channels, 2)
        let samples = [Float](unsafeUninitializedCapacity: frames * channels) { buf, count in
            for i in 0..<frames {
                let at = d.lowerBound + i * f.blockAlign
                for c in 0..<channels { buf[i * channels + c] = convert(at + c * width) }
            }
            count = frames * channels
        }
        return AudioBuffer(sampleRate: f.rate, channelCount: channels, samples: samples)
    }
}
