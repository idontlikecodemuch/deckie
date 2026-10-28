internal import CDrMp3
import Foundation

/// MP3 (MPEG-1, 2 and 2.5 audio, layers I to III) through dr_mp3, the vendored public-domain C decoder
/// (`Sources/CDrMp3`; version, SHA-256 and licence in DEPENDENCIES.md), decoded from memory to 32-bit float at the
/// file's own sample rate, then trimmed the way the lab's decoder trims, so the samples line up with the lab's
/// `soundfile.read(..., dtype="float32")` (libsndfile, which decodes MP3 through mpg123) to the sample.
///
/// An MP3 holds one or two channels (dr_mp3 decodes the stereo core and ignores MPEG-2's multichannel extension),
/// so the channel count is kept as it is.
///
/// **Gapless trimming.** MPEG audio comes out longer than what went in. The encoder adds an encoder delay at the
/// start (576 samples for LAME and for ffmpeg writing through LAME) and padding at the end to fill the last frame
/// (a layer III frame holds 1,152 samples per channel at 32 to 48 kHz, 576 below); the decoder adds 529 more at the
/// start (its filter bank's 528-sample overlap, plus 1; mpg123 calls it GAPLESS_DELAY). LAME records the delay and
/// the padding in the file's first frame, which carries no audio: a "Xing" tag (variable bit rate) or an "Info" tag
/// (constant), then LAME's 36-byte extension. Offsets in bytes from the "Xing"/"Info" word, numbers big-endian:
///
///     0-3    "Xing" or "Info"
///     4-7    flags: 0x1 frame count, 0x2 stream size, 0x4 seek table, 0x8 quality; the fields present follow
///            in that order, 4, 4, 100 and 4 bytes
///     8-11   the frame count (when flag 0x1 is set): audio frames in the stream, not counting the tag's own
///     then   LAME's extension, read when its first byte is not 0:
///              +0-8    encoder string, such as "LAME3.100", or "Lavf lame" from ffmpeg
///              +21-23  encoder delay (the first 12 bits) and padding (the last 12 bits), in samples
///
/// The decoded frames kept are `[delay + 529, frameCount × samplesPerFrame - padding + 529)`, clamped to what was
/// decoded: delay + 529 skipped at the start, padding - 529 dropped at the end. Without a tag frame, nothing is
/// trimmed. Where mpg123 and ffmpeg disagree this follows mpg123, the lab's decoder, as measured with libsndfile
/// 1.2.2 (soundfile 0.14.0) on edited copies of tone.mp3 (the cases are in MP3DecodeTests.swift): the extension
/// counts whatever its encoder string says (ffmpeg trusts only "LAME", "Lavf" and "Lavc"); a tag without the
/// extension still has the decoder's 529 skipped (ffmpeg skips nothing); a tag without the frame count trims
/// nothing (ffmpeg still skips delay + 529). dr_mp3 reads the tag and trims by itself too, by a rule that differs
/// from mpg123's in those last two cases, so its own trimming is switched off and the rule lives here, where a
/// dr_mp3 update cannot move it.
///
/// **Where the first frame starts.** dr_mp3 finds the tag only when the first frame begins exactly where it starts
/// decoding. Behind a second ID3v2 tag, or stray bytes after the tag, it decodes the tag frame as 1,152 samples of
/// silence and trims nothing (tone.mp3 came out 51 ms late). So this reader skips the ID3v2 tags itself, finds the
/// first frame with dr_mp3's own frame search, and hands dr_mp3 the bytes from that frame on.
enum MP3Reader {
    /// Samples every MPEG audio decoder adds at the start: the filter bank's 528-sample overlap, plus 1.
    static let decoderDelay = 529

    static func decode(_ data: Data, file: String) throws(AudioDecodeError) -> AudioBuffer {
        try decodeUntrimmed(data, file: file).trimmed()
    }

    /// Everything dr_mp3 decoded after the tag frame, before trimming, with what the trimming reads.
    struct Untrimmed {
        var buffer: AudioBuffer
        /// Where the first MPEG audio frame (the tag frame, when there is one) starts in the file.
        var firstFrameOffset: Int
        /// 1,152 for MPEG-1 layer III and for layer II, 576 for MPEG-2 and 2.5 layer III, 384 for layer I.
        var samplesPerFrame: Int
        /// The first frame's Xing or Info tag, nil when the first frame is audio.
        var tag: XingTag?

        /// The frames the lab's decoder keeps; see the type's comment.
        var kept: Range<Int> {
            guard let tag, let count = tag.frameCount, count > 0 else { return 0..<buffer.frames }
            let delay = tag.lame?.delay ?? 0, padding = tag.lame?.padding ?? 0
            let end = max(0, min(buffer.frames, count * samplesPerFrame - padding + MP3Reader.decoderDelay))
            return min(delay + MP3Reader.decoderDelay, end)..<end
        }

        func trimmed() -> AudioBuffer {
            let k = kept, c = buffer.channelCount
            if k == 0..<buffer.frames { return buffer }
            return AudioBuffer(sampleRate: buffer.sampleRate, channelCount: c,
                               samples: Array(buffer.samples[(k.lowerBound * c)..<(k.upperBound * c)]))
        }
    }

    /// A Xing or Info tag, parsed from its bytes starting at the "Xing"/"Info" word (layout in the type's comment).
    struct XingTag: Equatable {
        /// Audio frames in the stream, not counting the tag's own; nil when the tag leaves it out.
        var frameCount: Int?
        /// LAME's extension; nil when it is absent (its first byte 0, or the frame too short to hold it).
        var lame: LAMEExtension?

        struct LAMEExtension: Equatable {
            /// The encoder string's printable start, such as "LAME3.100" or "Lavf lame"; for reports only.
            var encoder: String
            /// Encoder delay and padding in samples, 12 bits each.
            var delay: Int
            var padding: Int
        }

        init(frameCount: Int?, lame: LAMEExtension?) {
            self.frameCount = frameCount
            self.lame = lame
        }

        init?(_ b: [UInt8]) {
            guard b.count >= 8, b[0..<4].elementsEqual("Xing".utf8) || b[0..<4].elementsEqual("Info".utf8) else {
                return nil
            }
            let flags = b[7]
            var o = 8
            if flags & 0x1 != 0 {
                guard b.count >= o + 4 else { return nil }
                frameCount = b[o..<(o + 4)].reduce(0) { $0 << 8 | Int($1) }
                o += 4
            }
            if flags & 0x2 != 0 { o += 4 }  // stream size in bytes
            if flags & 0x4 != 0 { o += 100 }  // seek table
            if flags & 0x8 != 0 { o += 4 }  // quality
            if b.count >= o + 36 && b[o] != 0 {
                lame = LAMEExtension(
                    encoder: String(decoding: b[o..<(o + 9)].prefix { $0 >= 0x20 && $0 < 0x7F }, as: UTF8.self),
                    delay: Int(b[o + 21]) << 4 | Int(b[o + 22]) >> 4,
                    padding: Int(b[o + 22] & 0x0F) << 8 | Int(b[o + 23]))
            }
        }
    }

    static func decodeUntrimmed(_ data: Data, file: String) throws(AudioDecodeError) -> Untrimmed {
        let result: Result<Untrimmed, AudioDecodeError> = data.withUnsafeBytes { raw in
            do throws(AudioDecodeError) {
                return .success(try decodeUntrimmed(raw, file: file))
            } catch {
                return .failure(error)
            }
        }
        return try result.get()
    }

    private static func decodeUntrimmed(_ raw: UnsafeRawBufferPointer,
                                        file: String) throws(AudioDecodeError) -> Untrimmed {
        func damaged(_ m: String) -> AudioDecodeError { .init(kind: .damaged, file: file, format: .mp3, message: m) }
        // dr_mp3 counts bytes in a C int.
        guard raw.count <= Int(Int32.max) else {
            throw AudioDecodeError(kind: .unsupported, file: file, format: .mp3,
                                   message: "MP3 files over 2 GB are not supported")
        }
        let tags = id3v2End(raw)
        guard !tags.overrun else { throw damaged("the ID3v2 tag at the start claims more bytes than the file holds") }
        guard let first = firstFrame(raw, from: tags.end) else {
            let after = tags.end > 0 ? " after the ID3v2 tag (\(tags.end) bytes)" : ""
            throw damaged("no complete MPEG audio frame found\(after); the file may be cut short, or not be MP3")
        }
        let start = raw.baseAddress! + first.offset

        let mp3 = UnsafeMutablePointer<drmp3>.allocate(capacity: 1)
        defer { mp3.deallocate() }
        // dr_mp3 hands over the tag frame it skips (from the "Xing"/"Info" word to the frame's end) through this
        // callback. It labels an Info tag as VBRI, hence the second type; the bytes are checked when parsed.
        var tagBytes: [UInt8]? = nil
        let opened = withUnsafeMutablePointer(to: &tagBytes) { tagBytesPointer in
            drmp3_init_memory_with_metadata(mp3, start, raw.count - first.offset, { user, metadata in
                guard let user, let m = metadata?.pointee, let bytes = m.pRawData,
                      m.type == DRMP3_METADATA_TYPE_XING || m.type == DRMP3_METADATA_TYPE_VBRI else { return }
                user.assumingMemoryBound(to: [UInt8]?.self).pointee =
                    Array(UnsafeRawBufferPointer(start: bytes, count: m.rawDataSize))
            }, tagBytesPointer, nil)
        }
        guard opened != 0 else { throw damaged("dr_mp3 could not open the stream at byte \(first.offset)") }
        defer { drmp3_uninit(mp3) }
        mp3.pointee.onMeta = nil  // the callback's pointer is gone after the call above
        // dr_mp3's own trimming off (see the type's comment): nothing skipped, no end set.
        mp3.pointee.delayInPCMFrames = 0
        mp3.pointee.paddingInPCMFrames = 0
        mp3.pointee.totalPCMFrameCount = UInt64.max  // DRMP3_UINT64_MAX: "length unknown"

        let channels = Int(mp3.pointee.channels), rate = Int(mp3.pointee.sampleRate)
        guard channels > 0, rate > 0 else { throw damaged("the first frame gives no channels or no sample rate") }
        var samples = [Float]()
        let chunk = 16 * 1152
        var buffer = [Float](repeating: 0, count: chunk * channels)
        while true {
            let read = Int(buffer.withUnsafeMutableBufferPointer {
                drmp3_read_pcm_frames_f32(mp3, UInt64(chunk), $0.baseAddress)
            })
            if read == 0 { break }
            samples.append(contentsOf: buffer[0..<(read * channels)])
        }
        guard !samples.isEmpty else { throw damaged("no audio frame could be decoded") }
        return Untrimmed(buffer: AudioBuffer(sampleRate: rate, channelCount: channels, samples: samples),
                         firstFrameOffset: first.offset, samplesPerFrame: first.samplesPerFrame,
                         tag: tagBytes.flatMap { XingTag($0) })
    }

    /// Where the ID3v2 tags at the start end, one after another: "ID3", two version bytes, a flags byte, the size
    /// in four 7-bit bytes, the body, and a 10-byte footer when flag 0x10 says so (ID3v2.4). `overrun` when a tag
    /// claims more bytes than the file holds.
    static func id3v2End(_ b: UnsafeRawBufferPointer) -> (end: Int, overrun: Bool) {
        var o = 0
        while o + 10 <= b.count, b[o] == 0x49, b[o + 1] == 0x44, b[o + 2] == 0x33, b[o + 3] != 0xFF, b[o + 4] != 0xFF,
              (b[o + 6] | b[o + 7] | b[o + 8] | b[o + 9]) & 0x80 == 0 {
            let size = Int(b[o + 6]) << 21 | Int(b[o + 7]) << 14 | Int(b[o + 8]) << 7 | Int(b[o + 9])
            o += 10 + size + (b[o + 5] & 0x10 != 0 ? 10 : 0)
            if o > b.count { return (b.count, true) }
        }
        return (o, false)
    }

    /// The first MPEG audio frame at or after `from`, by dr_mp3's own frame search (a candidate counts when the
    /// frames after it follow on with matching headers). That search reports where the frame ends; the start is
    /// the end less the frame's length, read from its header.
    static func firstFrame(_ b: UnsafeRawBufferPointer, from: Int) -> (offset: Int, samplesPerFrame: Int)? {
        guard from < b.count, let base = b.baseAddress else { return nil }
        let dec = UnsafeMutablePointer<drmp3dec>.allocate(capacity: 1)
        defer { dec.deallocate() }
        drmp3dec_init(dec)
        var info = drmp3dec_frame_info()
        let bytes = base.assumingMemoryBound(to: UInt8.self) + from
        _ = drmp3dec_decode_frame(dec, bytes, Int32(b.count - from), nil, &info)  // nil: find the frame, no samples
        guard info.layer != 0, info.frame_bytes > 0 else { return nil }
        let end = from + Int(info.frame_bytes)
        let h = withUnsafeBytes(of: dec.pointee.header) { Array($0) }
        guard let frame = FrameHeader(h), let length = frame.length(freeFormatBytes: Int(dec.pointee.free_format_bytes)),
              end - length >= from else {
            // dr_mp3 clears the header when the frame's side information does not parse. It then skips that frame
            // itself, so start where the search started; samplesPerFrame only matters with a tag, which needs a
            // frame that parses.
            return (from, 1152)
        }
        return (end - length, frame.samplesPerFrame)
    }

    /// The facts of a 4-byte MPEG audio frame header that locate the frame, computed as dr_mp3 computes them
    /// (drmp3_hdr_frame_samples, drmp3_hdr_frame_bytes, drmp3_hdr_padding).
    struct FrameHeader {
        var mpeg1: Bool, layer: Int, bitrateIndex: Int, sampleRate: Int, padded: Bool

        /// Bit rates in kbit/s by [MPEG-1 or not][layer - 1][index], the ISO 11172-3 and 13818-3 tables.
        static let kbps: [[[Int]]] = [
            [[0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256],  // MPEG-2 and 2.5, layer I
             [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],  // layer II
             [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160]],  // layer III
            [[0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448],  // MPEG-1, layer I
             [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384],  // layer II
             [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320]],  // layer III
        ]

        /// nil unless the bytes are a header dr_mp3 accepts (drmp3_hdr_valid): the sync bits, MPEG-1 or 2 with any
        /// layer or MPEG-2.5 with layer III, and no reserved layer, bit rate or sample rate.
        init?(_ h: [UInt8]) {
            guard h.count == 4, h[0] == 0xFF, h[1] & 0xF0 == 0xF0 || h[1] & 0xFE == 0xE2, h[1] & 0x06 != 0,
                  h[2] >> 4 != 15, (h[2] >> 2) & 3 != 3 else { return nil }
            mpeg1 = h[1] & 0x08 != 0
            let mpeg25 = h[1] & 0x10 == 0
            layer = 4 - Int((h[1] >> 1) & 3)  // the bits 11, 10, 01 are layers I, II, III
            bitrateIndex = Int(h[2] >> 4)
            sampleRate = [44100, 48000, 32000][Int((h[2] >> 2) & 3)] >> ((mpeg1 ? 0 : 1) + (mpeg25 ? 1 : 0))
            padded = h[2] & 0x02 != 0
        }

        var samplesPerFrame: Int { layer == 1 ? 384 : layer == 3 && !mpeg1 ? 576 : 1152 }

        /// Bytes, padding included. A free-format frame (bit-rate index 0) has the length dr_mp3 measured; nil
        /// when that is unknown.
        func length(freeFormatBytes: Int) -> Int? {
            var bytes = samplesPerFrame * Self.kbps[mpeg1 ? 1 : 0][layer - 1][bitrateIndex] * 125 / sampleRate
            if layer == 1 { bytes &= ~3 }  // whole 4-byte slots
            if bytes == 0 { bytes = freeFormatBytes }
            guard bytes > 0 else { return nil }
            return bytes + (padded ? (layer == 1 ? 4 : 1) : 0)
        }
    }
}
