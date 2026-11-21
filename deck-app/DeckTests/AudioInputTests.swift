import AVFoundation
import Foundation
import Testing
@testable import Deck

/// The sound input's plumbing, without an iPad: which channels are heard and recorded (`ChannelMap`), the set
/// recorder's counts and its "nothing was recorded" verdict, and what listening does on an interruption or a change of
/// input (`ListenGuard`), driven by made-up events. No sound is played and no microphone is used; nothing waits on a
/// clock (the guard is handed its times).
@Suite(.serialized) struct AudioInputTests {

    // MARK: helpers

    /// A buffer of `channels` separate (or interleaved) channels where channel c holds `value(c, frame)`.
    static func buffer(channels n: Int, frames: Int, rate: Double = 48000, interleaved: Bool = false,
                       _ value: (Int, Int) -> Float) throws -> AVAudioPCMBuffer {
        let f: AVAudioFormat
        if n <= 2 {
            f = try #require(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, channels: AVAudioChannelCount(n), interleaved: interleaved))
        } else {
            let layout = try #require(AVAudioChannelLayout(layoutTag: kAudioChannelLayoutTag_DiscreteInOrder | UInt32(n)))
            f = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate, interleaved: interleaved, channelLayout: layout)
        }
        let b = try #require(AVAudioPCMBuffer(pcmFormat: f, frameCapacity: AVAudioFrameCount(frames)))
        b.frameLength = AVAudioFrameCount(frames)
        let data = try #require(b.floatChannelData)
        for c in 0..<n {
            for i in 0..<frames {
                if interleaved { data[0][i * n + c] = value(c, i) } else { data[c][i] = value(c, i) }
            }
        }
        return b
    }
    static func channel(_ b: AVAudioPCMBuffer, _ c: Int) -> [Float] {
        Array(UnsafeBufferPointer(start: b.floatChannelData![c], count: Int(b.frameLength)))
    }
    /// Channel c's sample i in the made-up buffers: distinct for every channel and frame.
    static func tone(_ c: Int, _ i: Int) -> Float { Float(c + 1) * 0.1 + Float(i % 7) * 0.001 }

    // MARK: channels (ChannelMap)

    @Test func whichChannelsAreKept() {
        #expect(ChannelMap.kept(1) == 1)
        #expect(ChannelMap.kept(2) == 2)
        #expect(ChannelMap.kept(4) == 2)
        #expect(ChannelMap.kept(8) == 2)
        #expect(ChannelMap.leftOut(1) == nil && ChannelMap.leftOut(2) == nil)
        #expect(ChannelMap.leftOut(4) == 3...4)
        #expect(ChannelMap.leftOut(8) == 3...8)
    }

    @Test func separateChannelsAsArrays() {
        let mono: [[Float]] = [[0.1, 0.2, 0.3]]
        #expect(ChannelMap.mix(planar: mono, output: 1) == mono)
        #expect(ChannelMap.mix(planar: mono, output: 2) == [[0.1, 0.2, 0.3], [0.1, 0.2, 0.3]])        // mono on both sides
        let stereo: [[Float]] = [[0.2, 0.4], [0.6, 0.8]]
        #expect(ChannelMap.mix(planar: stereo, output: 2) == stereo)
        let down = ChannelMap.mix(planar: stereo, output: 1)
        #expect(down.count == 1 && abs(down[0][0] - 0.4) < 1e-6 && abs(down[0][1] - 0.6) < 1e-6)       // the two averaged
        let four: [[Float]] = [[1, 1], [2, 2], [3, 3], [4, 4]]
        #expect(ChannelMap.mix(planar: four, output: 2) == [[1, 1], [2, 2]])                          // inputs 1 and 2
        let eight = (0..<8).map { c in [Float](repeating: Float(c), count: 3) }
        #expect(ChannelMap.mix(planar: eight, output: 2) == [[0, 0, 0], [1, 1, 1]])
    }

    @Test func interleavedChannelsAsArrays() {
        // 4 channels, 3 frames: frame f, channel c holds 10 f + c
        let four: [Float] = (0..<3).flatMap { f in (0..<4).map { c in Float(10 * f + c) } }
        #expect(ChannelMap.mix(interleaved: four, channels: 4, output: 2) == [[0, 10, 20], [1, 11, 21]])
        let eight: [Float] = (0..<2).flatMap { f in (0..<8).map { c in Float(100 * f + c) } }
        #expect(ChannelMap.mix(interleaved: eight, channels: 8, output: 2) == [[0, 100], [1, 101]])
        let stereo: [Float] = [0.2, 0.6, 0.4, 0.8]
        let m = ChannelMap.mix(interleaved: stereo, channels: 2, output: 1)
        #expect(abs(m[0][0] - 0.4) < 1e-6 && abs(m[0][1] - 0.6) < 1e-6)
    }

    @Test(arguments: [(1, false), (2, false), (4, false), (8, false), (2, true), (4, true), (8, true)])
    func buffersOfEveryWidthKeepTheFirstPair(channels n: Int, interleaved: Bool) throws {
        let b = try Self.buffer(channels: n, frames: 512, interleaved: interleaved, Self.tone)
        let out = try #require(ChannelMap.apply(b))
        #expect(Int(out.format.channelCount) == min(2, n))
        #expect(!out.format.isInterleaved)
        #expect(out.format.sampleRate == 48000)
        #expect(out.frameLength == 512)
        for c in 0..<min(2, n) { #expect(Self.channel(out, c) == (0..<512).map { Self.tone(c, $0) }, "channel \(c + 1)") }
        // the inputs left out are watched for sound
        #expect((ChannelMap.peakLeftOut(b) > 0) == (n > 2))
    }

    @Test func aMicrophoneStillRecordsIntoAStereoFileAndStereoIntoMono() throws {
        let mono = try Self.buffer(channels: 1, frames: 64) { _, i in Float(i) / 64 }
        let wide = try #require(ChannelMap.apply(mono, channels: 2))
        #expect(Self.channel(wide, 0) == Self.channel(mono, 0) && Self.channel(wide, 1) == Self.channel(mono, 0))
        let stereo = try Self.buffer(channels: 2, frames: 64) { c, _ in c == 0 ? 0.2 : 0.6 }
        let narrow = try #require(ChannelMap.apply(stereo, channels: 1))
        #expect(Self.channel(narrow, 0).allSatisfy { abs($0 - 0.4) < 1e-6 })
    }

    @Test func quietLeftOutInputsAreNotCalledSound() throws {
        let b = try Self.buffer(channels: 4, frames: 256) { c, _ in c < 2 ? 0.5 : 0.0001 }
        #expect(ChannelMap.peakLeftOut(b) < CaptureSink.leftOutSound)
        let loud = try Self.buffer(channels: 4, frames: 256) { c, _ in c < 2 ? 0 : 0.3 }
        #expect(ChannelMap.peakLeftOut(loud) > CaptureSink.leftOutSound)
    }

    // MARK: the recorder's counts (RecordingTally)

    @Test func theTallySaysHowLongAndWhenNothingWasRecorded() {
        var t = RecordingTally(sampleRate: 48000)
        #expect(t.nothingRecorded && t.seconds == 0 && t.trouble == nil)
        #expect(t.wrote(48000) == false)
        #expect(!t.nothingRecorded && t.seconds == 1 && t.written == 1)
        // a problem is said once when it starts, counted every time, and ends with the next buffer written
        #expect(t.fail("disk full") == "disk full")
        #expect(t.fail("disk full") == nil)
        #expect(t.skip("odd buffer") == nil)
        #expect(t.trouble == "disk full" && t.failed == 2 && t.skipped == 1)
        #expect(t.wrote(24000) == true)
        #expect(t.trouble == nil && t.seconds == 1.5 && t.written == 2)
        // a recording that only ever failed has nothing in it
        var bad = RecordingTally(sampleRate: 44100)
        _ = bad.fail("no space")
        #expect(bad.nothingRecorded && bad.trouble == "no space")
    }

    /// The recorder with real files (in Documents/Sets, removed after): a 4-channel interface is recorded from its
    /// first pair, every buffer counted; a mono microphone after the input changed is fitted into the same file
    /// (channels and sample rate); a gap is noted in the log; the summary says how long was recorded.
    @Test func aFourChannelInterfaceIsRecordedAndCounted() throws {
        let r = SetRecorder()
        let four = try Self.buffer(channels: 4, frames: 4800, rate: 48000) { c, i in c < 2 ? 0.25 * sin(Float(i) * 0.05) : 0.2 }
        try r.begin(format: four.format)
        let name = try #require(r.baseName)
        defer { for ext in [".aac", " log.json", " tracklist.txt"] { try? FileManager.default.removeItem(at: SetRecorder.folder.appendingPathComponent(name + ext)) } }
        let sink = CaptureSink(ears: [], recorder: r) { _ in }
        for _ in 0..<10 { sink.take(four, at: nil) }      // 1 s
        r.gap(seconds: 12, why: ListenGuard.whyInterrupted)
        // the input is now the iPad's own microphone: mono, 44.1 kHz
        let mic = try Self.buffer(channels: 1, frames: 4410, rate: 44100) { _, i in 0.25 * sin(Float(i) * 0.05) }
        for _ in 0..<10 { sink.take(mic, at: nil) }       // 1 s more
        r.settle()
        let c = r.counts
        #expect(c.failed == 0 && c.skipped == 0)
        #expect(c.written >= 19)                           // the converter may hold the very first samples back
        #expect(abs(c.seconds - 2) < 0.05, "\(c.seconds) s")
        #expect(r.trouble == nil)
        let done = try #require(r.finish())
        #expect(!done.nothingRecorded && done.gaps == 1 && done.gapSeconds == 12)
        #expect(!r.isActive && r.finish() == nil)
        // the file is stereo and holds sound; the log has the gap, the left-out inputs and the summary
        let file = try AVAudioFile(forReading: SetRecorder.folder.appendingPathComponent(name + ".aac"))
        #expect(file.processingFormat.channelCount == 2)
        #expect(file.length > 48000)
        let log = try JSONDecoder().decode(SetRecorder.Log.self, from: Data(contentsOf: SetRecorder.folder.appendingPathComponent(name + " log.json")))
        let summary = try #require(log.summary)
        #expect(!summary.nothingRecorded && abs(summary.seconds - 2) < 0.1 && summary.buffersFailed == 0 && summary.gaps == 1)
        let notes = (log.notes ?? []).map(\.text).joined(separator: "\n")
        #expect(notes.contains("gap of 12 s"), "\(notes)")
        #expect(notes.contains("inputs 3–4 of 4 carry sound"), "\(notes)")
        let list = try String(contentsOf: SetRecorder.folder.appendingPathComponent(name + " tracklist.txt"), encoding: .utf8)
        // about 2 s (the sample-rate converter holds back a few samples, so the clock may read 0:00:01)
        #expect(list.contains("ended: 0:00:01 recorded") || list.contains("ended: 0:00:02 recorded"), "\(list)")
        #expect(!list.contains("nothing was recorded"))
    }

    @Test func aRecordingWithNoSoundSaysNothingWasRecorded() throws {
        let r = SetRecorder()
        let f = try #require(AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1))
        try r.begin(format: f)
        let name = try #require(r.baseName)
        defer { for ext in [".aac", " log.json", " tracklist.txt"] { try? FileManager.default.removeItem(at: SetRecorder.folder.appendingPathComponent(name + ext)) } }
        let done = try #require(r.finish())
        #expect(done.nothingRecorded && done.seconds == 0)
        let log = try JSONDecoder().decode(SetRecorder.Log.self, from: Data(contentsOf: SetRecorder.folder.appendingPathComponent(name + " log.json")))
        #expect(log.summary?.nothingRecorded == true)
        let list = try String(contentsOf: SetRecorder.folder.appendingPathComponent(name + " tracklist.txt"), encoding: .utf8)
        #expect(list.contains("nothing was recorded"))
    }

    @Test func pausedBuffersAreCountedButNotAProblem() throws {
        let r = SetRecorder()
        let b = try Self.buffer(channels: 2, frames: 4800) { _, _ in 0.1 }
        try r.begin(format: b.format)
        let name = try #require(r.baseName)
        defer { for ext in [".aac", " log.json", " tracklist.txt"] { try? FileManager.default.removeItem(at: SetRecorder.folder.appendingPathComponent(name + ext)) } }
        r.paused = true
        r.append(b); r.append(b)
        r.paused = false
        r.append(b)
        r.settle()
        let c = r.counts
        #expect(c.paused == 2 && c.written == 1 && c.trouble == nil && abs(c.seconds - 0.1) < 1e-9)
        r.finish()
    }

    // MARK: what REC says (RecChip)

    @Test func theRecChipTellsTheTruth() {
        func chip(on: Bool = true, active: Bool = true, paused: Bool = false, failed: Bool = false, trouble: Bool = false, hearing: Bool = true) -> RecChip {
            RecChip.now(recordingOn: on, active: active, paused: paused, failed: failed, trouble: trouble, hearing: hearing, seconds: 754)
        }
        #expect(chip(on: false) == .off && chip(on: false).words == "REC off")
        #expect(chip(active: false) == .notRecording && chip(active: false).words == "not recording")     // listening stopped
        #expect(chip(active: false, failed: true) == .cannotRecord && chip(active: false, failed: true).words == "cannot record")
        #expect(chip(trouble: true) == .cannotRecord)
        #expect(chip(paused: true) == .paused && chip(paused: true).words == "REC paused")
        #expect(chip(hearing: false) == .waiting && chip(hearing: false).words == "REC waiting")
        #expect(chip() == .recording(seconds: 754) && chip().words == "REC 0:12:34" && chip().live)
        #expect(!chip(hearing: false).live && !chip(active: false).live && !chip(paused: true).live)
    }

    // MARK: interruptions and changes of input (ListenGuard)

    static let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
    static let mic = AudioShape(sampleRate: 48000, channels: 1)
    static let interface = AudioShape(sampleRate: 44100, channels: 4)

    @Test func aCallStopsListeningAndItComesBackWhenTheCallEnds() {
        var g = ListenGuard()
        #expect(g.handle(.started(Self.mic), now: Self.t0).isEmpty && g.state == .running && g.hearing)
        #expect(g.handle(.interruptionBegan, now: Self.t0 + 1) == [.gapBegan(why: ListenGuard.whyInterrupted), .pauseCapture])
        #expect(g.state == .interrupted && !g.hearing)
        #expect(g.handle(.interruptionBegan, now: Self.t0 + 2).isEmpty)                   // said twice: nothing more
        #expect(g.handle(.configurationChanged, now: Self.t0 + 3).isEmpty)                // the start at the end takes the input as it is
        #expect(g.handle(.tick, now: Self.t0 + 30).isEmpty && g.state == .interrupted)    // no retrying through a call
        #expect(g.handle(.interruptionEnded(shouldResume: true), now: Self.t0 + 41) == [.restartCapture])
        #expect(g.state == .restarting)
        #expect(g.handle(.restarted(Self.mic), now: Self.t0 + 41) == [.gapEnded(seconds: 40, why: ListenGuard.whyInterrupted)])
        #expect(g.state == .running && g.shape == Self.mic && g.gapStart == nil)
    }

    @Test func anInterruptionEndedWithoutResumeIsTriedAgainEveryFewSeconds() {
        var g = ListenGuard()
        _ = g.handle(.started(Self.mic), now: Self.t0)
        _ = g.handle(.interruptionBegan, now: Self.t0)
        #expect(g.handle(.interruptionEnded(shouldResume: false), now: Self.t0 + 10).isEmpty)
        #expect(g.state == .stalled(ListenGuard.whyInterrupted))
        #expect(g.handle(.tick, now: Self.t0 + 12).isEmpty)                               // not yet
        #expect(g.handle(.tick, now: Self.t0 + 15) == [.restartCapture])
        #expect(g.handle(.restartFailed("busy"), now: Self.t0 + 15).isEmpty && g.state == .stalled("busy"))
        #expect(g.handle(.tick, now: Self.t0 + 19).isEmpty)
        #expect(g.handle(.tick, now: Self.t0 + 20) == [.restartCapture])
        #expect(g.handle(.restarted(Self.mic), now: Self.t0 + 20) == [.gapEnded(seconds: 20, why: ListenGuard.whyInterrupted)])
        #expect(g.state == .running)
    }

    @Test func comingToTheFrontStartsAnInterruptedListenAgain() {
        // iPadOS does not always say an interruption ended
        var g = ListenGuard()
        _ = g.handle(.started(Self.mic), now: Self.t0)
        _ = g.handle(.interruptionBegan, now: Self.t0)
        #expect(g.handle(.appActive, now: Self.t0 + 5) == [.restartCapture])
        // while hearing, coming to the front changes nothing
        _ = g.handle(.restarted(Self.mic), now: Self.t0 + 5)
        #expect(g.handle(.appActive, now: Self.t0 + 6).isEmpty && g.state == .running)
    }

    @Test func aNewInputFormatIsPassedOn() {
        var g = ListenGuard()
        _ = g.handle(.started(Self.mic), now: Self.t0)
        // an interface plugged in: the engine stops itself and says its configuration changed
        #expect(g.handle(.configurationChanged, now: Self.t0 + 1) == [.gapBegan(why: ListenGuard.whyInputChanged), .restartCapture])
        #expect(g.handle(.routeChanged(.deviceAdded), now: Self.t0 + 1).isEmpty)          // already in hand
        let out = g.handle(.restarted(Self.interface), now: Self.t0 + 1.5)
        #expect(out == [.gapEnded(seconds: 0.5, why: ListenGuard.whyInputChanged), .formatChanged(from: Self.mic, to: Self.interface)])
        #expect(g.shape == Self.interface)
    }

    @Test func unpluggingTheInterfaceGoesBackToTheMicrophone() {
        var g = ListenGuard()
        _ = g.handle(.started(Self.interface), now: Self.t0)
        #expect(g.handle(.routeChanged(.deviceRemoved), now: Self.t0 + 1) == [.gapBegan(why: ListenGuard.whyInputChanged), .restartCapture])
        #expect(g.handle(.restarted(Self.mic), now: Self.t0 + 1) == [.gapEnded(seconds: 0, why: ListenGuard.whyInputChanged),
                                                                     .formatChanged(from: Self.interface, to: Self.mic)])
        // a route change that is not about the input changes nothing
        #expect(g.handle(.routeChanged(.other), now: Self.t0 + 2).isEmpty && g.state == .running)
    }

    @Test func noInputWaitsAndAnInputPluggedInStartsAtOnce() {
        var g = ListenGuard()
        _ = g.handle(.started(Self.interface), now: Self.t0)
        #expect(g.handle(.routeChanged(.noInput), now: Self.t0 + 1) == [.gapBegan(why: ListenGuard.whyNoInput), .pauseCapture])
        #expect(g.state == .stalled(ListenGuard.whyNoInput))
        #expect(g.handle(.routeChanged(.deviceAdded), now: Self.t0 + 2) == [.restartCapture])
        #expect(g.handle(.restarted(Self.interface), now: Self.t0 + 3) == [.gapEnded(seconds: 2, why: ListenGuard.whyNoInput)])
    }

    @Test func listeningThatCouldNotStartKeepsTrying() {
        var g = ListenGuard()
        #expect(g.handle(.startFailed("busy"), now: Self.t0).isEmpty && g.state == .stalled("busy"))
        #expect(g.handle(.tick, now: Self.t0 + 5) == [.restartCapture])
        // the first start: no gap to end, no format to compare with
        #expect(g.handle(.restarted(Self.mic), now: Self.t0 + 5).isEmpty && g.state == .running && g.shape == Self.mic)
    }

    @Test func theAudioRestartingStartsListeningAgain() {
        var g = ListenGuard()
        _ = g.handle(.started(Self.mic), now: Self.t0)
        #expect(g.handle(.mediaReset, now: Self.t0) == [.gapBegan(why: ListenGuard.whyReset), .restartCapture])
    }

    @Test func nothingHappensWhenNotListeningAndStopForgetsAll() {
        var g = ListenGuard()
        for e: ListenGuard.Event in [.interruptionBegan, .interruptionEnded(shouldResume: true), .configurationChanged, .routeChanged(.deviceAdded),
                                     .routeChanged(.noInput), .mediaReset, .restarted(Self.mic), .restartFailed("x"), .appActive, .tick] {
            #expect(g.handle(e, now: Self.t0).isEmpty, "\(e)")
            #expect(g.state == .off)
        }
        _ = g.handle(.started(Self.mic), now: Self.t0)
        _ = g.handle(.interruptionBegan, now: Self.t0)
        #expect(g.handle(.stopped, now: Self.t0).isEmpty)
        #expect(g == ListenGuard())
    }

    // MARK: iPadOS's notifications as events

    @Test func interruptionNotificationsBecomeEvents() {
        typealias E = ListenGuard.Event
        let began: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]
        #expect(E.interruption(began) == .interruptionBegan)
        let resume: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                                          AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue]
        #expect(E.interruption(resume) == .interruptionEnded(shouldResume: true))
        let noResume: [AnyHashable: Any] = [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue]
        #expect(E.interruption(noResume) == .interruptionEnded(shouldResume: false))
        #expect(E.interruption(nil) == nil && E.interruption([:]) == nil)
    }

    @Test func routeChangeNotificationsBecomeEvents() {
        typealias E = ListenGuard.Event
        func info(_ r: AVAudioSession.RouteChangeReason) -> [AnyHashable: Any] { [AVAudioSessionRouteChangeReasonKey: r.rawValue] }
        #expect(E.routeChange(info(.newDeviceAvailable), hasInput: true) == .routeChanged(.deviceAdded))
        #expect(E.routeChange(info(.oldDeviceUnavailable), hasInput: true) == .routeChanged(.deviceRemoved))
        #expect(E.routeChange(info(.oldDeviceUnavailable), hasInput: false) == .routeChanged(.noInput))
        #expect(E.routeChange(info(.noSuitableRouteForCategory), hasInput: true) == .routeChanged(.noInput))
        #expect(E.routeChange(info(.categoryChange), hasInput: true) == .routeChanged(.other))
        #expect(E.routeChange(nil, hasInput: true) == nil)
    }

    // MARK: the session

    @Test func theSessionSuitsASet() {
        #expect(MicCapture.category == .playAndRecord)          // the record category would silence the DJ's own music on this iPad
        #expect(MicCapture.mode == .measurement)
        #expect(MicCapture.options.contains(.mixWithOthers))    // starting to listen never stops that music
        #expect(!MicCapture.options.contains(.duckOthers))
        #expect(!MicCapture.options.contains(.allowBluetoothHFP))  // no Bluetooth headset as the microphone
    }

    // MARK: the words

    @Test func theNewWordsKeepToTheVocabulary() {
        let all = ([Words.recNotRecording, Words.recCannot, Words.recWaiting, Words.recCannotFoot, Words.stoppedNothingRecorded,
                    Words.stoppedSavedLength("0:42:10"), Words.setSavedFootLength("0:42:10", empty: false), Words.setSavedFootLength(nil, empty: true)]
                   + [Recognizer.ListenTrouble.interrupted, .restarting, .cannotListen].flatMap {
                       [Words.listenTroubleStatus($0), Words.listenTroubleTitle($0), Words.listenTroubleFoot($0, recording: true), Words.listenTroubleFoot($0, recording: false)]
                   }).joined(separator: " ").lowercased()
        #expect(!all.contains("track"))
        #expect(!all.contains(" ai ") && !all.contains("ai."))
        #expect(!all.contains("booth"))
        for line in (Words.recCannotFoot + "\n" + Words.stoppedNothingRecorded + "\n" + Words.stoppedSavedLength("0:42:10")).split(separator: "\n") {
            #expect(line.contains("\u{00A0}"), "\(line) can end on one word")
        }
    }
}
