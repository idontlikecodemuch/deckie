import Foundation
import DeckieAudio
#if canImport(AudioToolbox)
import AudioToolbox
#endif

/// AAC and Apple Lossless on a Mac (and on Apple's other systems), through the system's own decoder: Core Audio's
/// `ExtAudioFile` (AudioToolbox), which every Mac has, so nothing is added to Deckie. It reads AAC and Apple Lossless in
/// an MP4 (`.m4a`, `.mp4`) and AAC as a raw ADTS stream (`.aac`), to 32-bit float at the file's own rate, the first two
/// channels kept as `AudioDecoder` keeps them.
///
/// Where the sound starts. Core Audio reads the file's own statement of its encoder's lead-in (the edit list or the
/// `iTunSMPB` tag) and leaves the lead-in out itself. What it hands back is then checked against what the file says
/// (`MP4Trim`, as for Windows' decoder): the length matches the true length, so nothing more is dropped. A file that
/// states its lead-in nowhere, and a raw `.aac` stream, which has no place to state it, is read and marked
/// `startUncertain`, as on Windows (D33).
enum AppleAudioReader {
    /// Whether this system has the decoder.
    static var available: Bool {
        #if canImport(AudioToolbox)
        return true
        #else
        return false
        #endif
    }

    struct Failure: Error, CustomStringConvertible {
        var message: String
        var description: String { message }
    }

    /// The whole file, as Core Audio decodes it.
    static func decodeRaw(_ url: URL) throws(Failure) -> DeckieAudio.AudioBuffer {
        #if canImport(AudioToolbox)
        var fileRef: ExtAudioFileRef?
        var status = ExtAudioFileOpenURL(url as CFURL, &fileRef)
        guard status == noErr, let file = fileRef else { throw Failure(message: "Core Audio could not open it (\(code(status)))") }
        defer { ExtAudioFileDispose(file) }

        var source = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileDataFormat, &size, &source)
        guard status == noErr, source.mSampleRate > 0, source.mChannelsPerFrame > 0 else {
            throw Failure(message: "Core Audio could not read its format (\(code(status)))")
        }
        let fileChannels = Int(source.mChannelsPerFrame)
        let channels = min(fileChannels, 2)
        // Float32 interleaved at the file's own rate, every channel the file has (the first two are kept below).
        var client = AudioStreamBasicDescription(
            mSampleRate: source.mSampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(4 * fileChannels), mFramesPerPacket: 1, mBytesPerFrame: UInt32(4 * fileChannels),
            mChannelsPerFrame: UInt32(fileChannels), mBitsPerChannel: 32, mReserved: 0)
        status = ExtAudioFileSetProperty(file, kExtAudioFileProperty_ClientDataFormat,
                                         UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &client)
        guard status == noErr else { throw Failure(message: "Core Audio cannot decode it here (\(code(status)))") }

        var expected: Int64 = 0
        size = UInt32(MemoryLayout<Int64>.size)
        if ExtAudioFileGetProperty(file, kExtAudioFileProperty_FileLengthFrames, &size, &expected) != noErr { expected = 0 }
        var samples: [Float] = []
        // The file's length is in its own rate's frames; the client's rate is the same.
        if expected > 0 { samples.reserveCapacity(Int(expected) * channels) }
        let chunk = 16_384
        var block = [Float](repeating: 0, count: chunk * fileChannels)
        while true {
            var frames = UInt32(chunk)
            status = block.withUnsafeMutableBytes { raw -> OSStatus in
                var list = AudioBufferList(mNumberBuffers: 1, mBuffers: .init(
                    mNumberChannels: UInt32(fileChannels), mDataByteSize: UInt32(raw.count), mData: raw.baseAddress))
                return ExtAudioFileRead(file, &frames, &list)
            }
            guard status == noErr else {
                if samples.isEmpty { throw Failure(message: "Core Audio could not decode it (\(code(status)))") }
                // Damaged past this point: what was read stands, and the analysis says whether it is enough.
                break
            }
            if frames == 0 { break }
            let n = Int(frames)
            if fileChannels == channels {
                samples.append(contentsOf: block[0..<(n * channels)])
            } else {
                for f in 0..<n { for c in 0..<channels { samples.append(block[f * fileChannels + c]) } }
            }
        }
        guard !samples.isEmpty else { throw Failure(message: "Core Audio decoded no audio from it") }
        return DeckieAudio.AudioBuffer(sampleRate: Int(source.mSampleRate.rounded()), channelCount: channels, samples: samples)
        #else
        throw Failure(message: "this system has no Core Audio")
        #endif
    }

    /// An `OSStatus` as its four letters when it is a four-character code, else as a number.
    static func code(_ status: Int32) -> String {
        let u = UInt32(bitPattern: status)
        let bytes = [UInt8(u >> 24 & 0xFF), UInt8(u >> 16 & 0xFF), UInt8(u >> 8 & 0xFF), UInt8(u & 0xFF)]
        if bytes.allSatisfy({ $0 >= 0x20 && $0 < 0x7F }) { return "'" + String(decoding: bytes, as: UTF8.self) + "'" }
        return String(status)
    }
}
