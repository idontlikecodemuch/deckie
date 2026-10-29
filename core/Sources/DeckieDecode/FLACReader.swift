internal import CDrFlac
import Foundation

/// FLAC through dr_flac, the vendored public-domain C decoder (`Sources/CDrFlac`; version, SHA-256 and licence in
/// DEPENDENCIES.md), decoded from memory to 32-bit float at the file's own sample rate. FLAC is lossless and has no
/// encoder delay, so nothing is trimmed: the samples are the ones that went in, each integer divided by 2^(bits - 1)
/// as libsndfile divides it, and they match the lab's `soundfile.read(..., dtype="float32")` to the bit.
///
/// Native FLAC ("fLaC") and FLAC in an Ogg container (Ogg-FLAC, "OggS"; dr_flac reads it by default, the lab's
/// libsndfile does not) are both read, at up to 24 bits per sample: dr_flac takes the frame header's code for 32 bits
/// as reserved and decodes no frame marked so, and the lab refuses such files too, so more than 24 bits is reported
/// as not supported. Mono stays mono, stereo stays stereo, more channels (FLAC holds up to eight) are cut to the first
/// two, as the lab does.
///
/// **ID3v2 tags in front.** Some taggers put an ID3v2 tag before "fLaC". dr_flac skips such tags when it looks for
/// the stream, but then reads the metadata blocks from absolute byte 42, which assumes there was no tag, so behind
/// one it fails to open the file. This reader skips the tags itself, as MP3Reader does, and hands dr_flac the bytes
/// from "fLaC" on.
///
/// **Damage.** dr_flac checks every frame's checksums. Left to itself it drops a frame that fails them and goes on
/// with the next good one, which brings the audio after it early and moves every beat after it; at a frame it
/// cannot parse, or where the file ends inside a frame, it returns no samples, as at the end of the stream, and if
/// asked again it carries on from the next frame it finds. The lab refuses files damaged like this (libsndfile:
/// "flac decoder lost sync"), and so does this reader, saying where: it reads one FLAC frame at a time and checks
/// that each frame's number (or, with variable block sizes, its first sample) follows on from the last; when dr_flac
/// returns nothing it checks that every byte was read, which is how a stream ends; and it checks the total against
/// the count in STREAMINFO. Each failing throws `.damaged`. Past that count it keeps nothing, as libsndfile keeps
/// nothing.
enum FLACReader {
    /// What was decoded, with the facts of the stream it came from.
    struct Decoded {
        var buffer: AudioBuffer
        /// Bits per sample in the file (16 and 24 in practice).
        var bitsPerSample: Int
        /// Channels in the file, before any past the second are cut.
        var fileChannels: Int
        /// True for FLAC in an Ogg container.
        var ogg: Bool
        /// Where "fLaC" or "OggS" starts: after the ID3v2 tags in front, if any.
        var streamOffset: Int
        /// The frame count STREAMINFO gives (samples per channel); nil when it says "unknown" (0).
        var declaredFrames: Int?
    }

    static func decode(_ data: Data, file: String) throws(AudioDecodeError) -> AudioBuffer {
        try decodeWithDetails(data, file: file).buffer
    }

    static func decodeWithDetails(_ data: Data, file: String) throws(AudioDecodeError) -> Decoded {
        let result: Result<Decoded, AudioDecodeError> = data.withUnsafeBytes { raw in
            do throws(AudioDecodeError) {
                return .success(try decode(raw, file: file))
            } catch {
                return .failure(error)
            }
        }
        return try result.get()
    }

    /// True when the bytes are the first page of an Ogg stream holding FLAC: "OggS", then (after the 27-byte page
    /// header and its table of segment lengths) a first packet that starts with 0x7F and "FLAC", as the Ogg mapping
    /// of FLAC lays it out.
    static func isOggFLAC(_ b: UnsafeRawBufferPointer) -> Bool {
        guard b.count >= 27, b[0] == 0x4F, b[1] == 0x67, b[2] == 0x67, b[3] == 0x53 else { return false }
        let packet = 27 + Int(b[26])
        guard b.count >= packet + 5 else { return false }
        return b[packet] == 0x7F && b[packet + 1] == 0x46 && b[packet + 2] == 0x4C && b[packet + 3] == 0x41
            && b[packet + 4] == 0x43
    }

    private static func decode(_ raw: UnsafeRawBufferPointer, file: String) throws(AudioDecodeError) -> Decoded {
        func damaged(_ m: String) -> AudioDecodeError { .init(kind: .damaged, file: file, format: .flac, message: m) }
        let tags = MP3Reader.id3v2End(raw)
        guard !tags.overrun else { throw damaged("the ID3v2 tag at the start claims more bytes than the file holds") }
        let stream = UnsafeRawBufferPointer(rebasing: raw[tags.end...])
        let native = stream.starts(with: "fLaC".utf8), ogg = isOggFLAC(stream)
        guard native || ogg else {
            let after = tags.end > 0 ? " after the ID3v2 tag (\(tags.end) bytes)" : ""
            throw damaged("no \"fLaC\" or Ogg-FLAC header\(after)")
        }
        // "fLaC" and the STREAMINFO block (4 + 34 bytes) are the least a native file holds before its frames.
        guard !native || stream.count >= 42 else { throw damaged("the file is cut short inside the FLAC header") }
        guard let flac = drflac_open_memory(stream.baseAddress, stream.count, nil) else {
            throw damaged("dr_flac could not read the stream header (STREAMINFO and the metadata blocks after it): "
                          + "the file is cut short or damaged there")
        }
        defer { drflac_close(flac) }

        let channels = Int(flac.pointee.channels), rate = Int(flac.pointee.sampleRate)
        let bits = Int(flac.pointee.bitsPerSample), declared = Int(flac.pointee.totalPCMFrameCount)
        guard channels > 0, rate > 0 else { throw damaged("STREAMINFO gives no channels or no sample rate") }
        guard bits <= 24 else {
            throw AudioDecodeError(kind: .unsupported, file: file, format: .flac,
                                   message: "\(bits)-bit FLAC is not supported (up to 24 bits is)")
        }
        let kept = min(channels, 2)
        func seconds(_ frames: Int) -> String { String(format: "%.3f s", Double(frames) / Double(rate)) }

        var samples = [Float]()
        // STREAMINFO's count is not trusted for memory: at most one frame per byte of the file is reserved.
        if declared > 0 { samples.reserveCapacity(min(declared, raw.count) * kept) }
        // One FLAC frame of samples; never empty, since dr_flac takes a null buffer as "skip these frames".
        var block = [Float](repeating: 0, count: max(1, Int(flac.pointee.maxBlockSizeInPCMFrames)) * channels)
        var decoded = 0  // samples per channel so far
        var frames = 0  // FLAC frames so far
        while true {
            // Between FLAC frames dr_flac holds no samples, so asking for one makes it decode the next frame: the
            // one that follows, or, past a frame that fails its checksums, the next good one.
            let first = block.withUnsafeMutableBufferPointer { drflac_read_pcm_frames_f32(flac, 1, $0.baseAddress) }
            if first == 0 { break }
            let header = flac.pointee.currentFLACFrame.header
            // A fixed-block-size stream numbers its frames 0, 1, 2...; a variable one gives each frame's first
            // sample instead (and dr_flac sets the other field to 0). Frame 0 starts at sample 0 either way.
            let inOrder = header.pcmFrameNumber != 0 ? Int(header.pcmFrameNumber) == decoded
                : header.flacFrameNumber != 0 ? Int(header.flacFrameNumber) == frames : decoded == 0
            guard inOrder else {
                throw damaged("the frame at \(seconds(decoded)) (sample \(decoded)) is damaged or missing: decoding "
                              + "past it would bring the audio after it early")
            }
            let rest = Int(flac.pointee.currentFLACFrame.pcmFramesRemaining)
            if rest > 0 {
                let read = block.withUnsafeMutableBufferPointer {
                    drflac_read_pcm_frames_f32(flac, UInt64(rest), $0.baseAddress! + channels)
                }
                guard read == rest else { throw damaged("dr_flac stopped inside the frame at \(seconds(decoded))") }
            }
            let n = 1 + rest
            if kept == channels {
                samples.append(contentsOf: block[0..<(n * channels)])
            } else {
                for f in 0..<n { samples.append(contentsOf: block[(f * channels)..<(f * channels + kept)]) }
            }
            decoded += n
            frames += 1
        }
        // dr_flac returns no samples both at the end and at a frame it cannot decode. At the end it has read every
        // byte, looking for another frame; short of that, decoding stopped at damage. (Damage in the last few KB,
        // which dr_flac has already read ahead, shows as a file cut short.)
        let read = flac.pointee.memoryStream
        let at = declared > 0
            ? "\(seconds(decoded)) of \(seconds(declared)) (\(decoded) of \(declared) samples per channel)"
            : "\(seconds(decoded)) (sample \(decoded))"
        if read.currentReadPos < read.dataSize {
            throw damaged("decoding stopped at \(at): the frame there is damaged")
        }
        if decoded < declared { throw damaged("decoding stopped at \(at): the file is cut short") }
        guard decoded > 0 else { throw damaged("no audio frame could be decoded") }
        if declared > 0 && decoded > declared { samples.removeLast((decoded - declared) * kept) }
        return Decoded(buffer: AudioBuffer(sampleRate: rate, channelCount: kept, samples: samples),
                       bitsPerSample: bits, fileChannels: channels, ogg: ogg, streamOffset: tags.end,
                       declaredFrames: declared > 0 ? declared : nil)
    }
}
