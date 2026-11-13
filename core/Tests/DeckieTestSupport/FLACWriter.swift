import Foundation
import DeckieAudio

/// Writes a FLAC file with no compression at all (every block "verbatim": the samples as they are), so the tests can
/// make a FLAC file on any platform with no encoder program, and the same audio always gives the same bytes. Any FLAC
/// decoder reads it; it is only larger than a real encoder's file. 16 bits, one or two channels, blocks of 4,096.
public enum FLACWriter {
    public static func flac16(_ buffer: AudioBuffer) -> Data {
        let ch = buffer.channelCount, rate = buffer.sampleRate
        precondition(ch == 1 || ch == 2, "one or two channels")
        let frames = buffer.samples.count / ch
        let pcm: [Int16] = buffer.samples.map { Int16(max(-32767, min(32767, ($0 * 32767).rounded()))) }
        let block = 4096
        var out = [UInt8]("fLaC".utf8)
        // STREAMINFO, the only metadata block (so its "last" bit is set): 34 bytes.
        out += [0x80, 0, 0, 34]
        out += [UInt8(block >> 8), UInt8(block & 0xFF), UInt8(block >> 8), UInt8(block & 0xFF)]
        out += [0, 0, 0, 0, 0, 0]  // smallest and largest frame size: not stated
        // 20 bits of sample rate, 3 of channels less one, 5 of bits per sample less one, 36 of total samples.
        let packed = UInt64(rate) << 44 | UInt64(ch - 1) << 41 | UInt64(15) << 36 | UInt64(frames)
        out += (0..<8).map { UInt8(packed >> UInt64(56 - 8 * $0) & 0xFF) }
        out += [UInt8](repeating: 0, count: 16)  // the MD5 of the audio: all zero means not stated
        let rateCode: UInt8
        switch rate {
        case 44100: rateCode = 0b1001
        case 48000: rateCode = 0b1010
        case 22050: rateCode = 0b0110
        default: preconditionFailure("44.1, 48 or 22.05 kHz")
        }
        var number = 0
        var at = 0
        while at < frames {
            let n = min(block, frames - at)
            var f: [UInt8] = [0xFF, 0xF8]  // sync, fixed block size
            f.append((n == block ? 0b1100 : 0b0111) << 4 | rateCode)  // 4,096, or "16 bits follow"
            f.append((ch == 2 ? 0b0001 : 0b0000) << 4 | 0b100 << 1)  // channels, 16 bits per sample
            f += utf8Number(number)
            if n != block { f += [UInt8((n - 1) >> 8), UInt8((n - 1) & 0xFF)] }
            f.append(crc8(f))
            for c in 0..<ch {
                f.append(0x02)  // a verbatim subframe, no wasted bits
                for i in at..<(at + n) {
                    let v = UInt16(bitPattern: pcm[i * ch + c])
                    f.append(UInt8(v >> 8)); f.append(UInt8(v & 0xFF))
                }
            }
            let sum = crc16(f)
            f += [UInt8(sum >> 8), UInt8(sum & 0xFF)]
            out += f
            at += n
            number += 1
        }
        return Data(out)
    }

    /// The frame number as FLAC writes it: the way UTF-8 writes a character code.
    static func utf8Number(_ v: Int) -> [UInt8] {
        if v < 0x80 { return [UInt8(v)] }
        if v < 0x800 { return [UInt8(0xC0 | v >> 6), UInt8(0x80 | v & 0x3F)] }
        if v < 0x10000 { return [UInt8(0xE0 | v >> 12), UInt8(0x80 | v >> 6 & 0x3F), UInt8(0x80 | v & 0x3F)] }
        return [UInt8(0xF0 | v >> 18), UInt8(0x80 | v >> 12 & 0x3F), UInt8(0x80 | v >> 6 & 0x3F), UInt8(0x80 | v & 0x3F)]
    }

    static func crc8(_ bytes: [UInt8]) -> UInt8 {
        var c: UInt8 = 0
        for b in bytes {
            c ^= b
            for _ in 0..<8 { c = c & 0x80 != 0 ? (c << 1) ^ 0x07 : c << 1 }
        }
        return c
    }

    static func crc16(_ bytes: [UInt8]) -> UInt16 {
        var c: UInt16 = 0
        for b in bytes {
            c ^= UInt16(b) << 8
            for _ in 0..<8 { c = c & 0x8000 != 0 ? (c << 1) ^ 0x8005 : c << 1 }
        }
        return c
    }
}
