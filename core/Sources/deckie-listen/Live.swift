import Foundation
import DeckieCrate
import DeckieDecode
import DeckieRecognition
import DeckieCapture

// deckie-listen --inputs
//     the inputs this computer has, the system's default marked (opens nothing, asks no permission).
// deckie-listen --live --crate <crate file> [--input NAME] [--seconds N] [--sound FILE] [--log FILE]
//     listens to an input (the system's default, or the one named) with the booth's listener and the crate's songs,
//     and prints once a second: seconds heard, the input's level (average and loudest, dB below full scale), samples at
//     full scale, and the song named (or "-"), with its place, how sure and the reading's milliseconds. The index is
//     kept in the system's temporary folder by the crate's songs, so the second run opens at once.
//     --sound FILE: a recording played as if heard, at the speed of sound, in place of an input (a check with no
//     microphone). --log FILE: every reading and level, tab-separated, for measuring. Stops with Ctrl+C or after
//     --seconds. The song shown is the listener's current named song (the iPad's switching rule is not applied).

func liveFail(_ message: String) -> Never { FileHandle.standardError.write(Data((message + "\n").utf8)); exit(2) }

func listInputs() -> Never {
    do {
        let listed = try SoundInputs.list()
        print("sound system: \(listed.system)")
        if listed.inputs.isEmpty { print("no inputs") }
        for i in listed.inputs { print((i.isDefault ? "* " : "  ") + i.name) }
        exit(0)
    } catch { liveFail("cannot list inputs: \(error)") }
}

final class LiveState: @unchecked Sendable {
    let lock = NSLock()
    var level: SoundLevel?
    var clippedSince = 0
    var reading: ListenReading?
    var ended: CaptureError?
    var log: FileHandle?
    func write(_ s: String) { lock.lock(); log?.write(Data((s + "\n").utf8)); lock.unlock() }
}

func runLive(_ values: [String: String], _ flags: Set<String>) -> Never {
    guard let cratePath = values["--crate"] else { liveFail("--live needs --crate <crate file>") }
    var package = URL(fileURLWithPath: cratePath)
    if CrateArchive.isArchive(package) {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("deckie-listen-\(UUID().uuidString).deckie")
        do { try CrateArchive.unpack(package, to: tmp) } catch { liveFail("cannot open \(cratePath): \(error)") }
        package = tmp
    }
    let crate: Crate
    do { crate = try CrateReader.read(from: package) } catch { liveFail("cannot read \(cratePath): \(error)") }
    let songs = crate.recognitionSongs()
    guard !songs.songs.isEmpty else { liveFail("no song in this crate has a fingerprint") }
    let cache = FileManager.default.temporaryDirectory.appendingPathComponent("deckie-listen-\(songs.stamp).dkx")
    let t0 = Date()
    let index: RecognitionIndex
    do { index = try songs.index(cachedAt: cache) } catch { liveFail("cannot make the index: \(error)") }
    var names: [String: String] = [:]
    for t in crate.tracks { names[t.id] = [t.ident.artist, t.ident.title].compactMap { $0 }.joined(separator: " - ") }
    FileHandle.standardError.write(Data(String(format: "crate: %d songs, %d with a fingerprint; index ready in %.1f s (%@)\n",
                                               crate.tracks.count, index.songCount, Date().timeIntervalSince(t0), cache.path).utf8))

    let source: SoundSource
    if let file = values["--sound"] {
        guard let b = try? AudioDecoder.decode(URL(fileURLWithPath: file)) else { liveFail("cannot decode \(file)") }
        source = SampleSource(name: URL(fileURLWithPath: file).lastPathComponent, samples: b.samples,
                              format: SoundFormat(rate: b.sampleRate, channels: b.channelCount), pace: 1,
                              endsWith: CaptureError("gone", "the recording ended"))
    } else {
        let listed: [SoundInput]
        do { listed = try SoundInputs.list().inputs } catch { liveFail("cannot list inputs: \(error)") }
        if let wanted = values["--input"], SoundInputs.named(wanted, in: listed) == nil {
            liveFail("no input named \(wanted); --inputs lists them")
        }
        source = Microphone(SoundInputs.named(values["--input"], in: listed))
    }
    let state = LiveState()
    if let path = values["--log"] {
        FileManager.default.createFile(atPath: path, contents: nil)
        state.log = FileHandle(forWritingAtPath: path)
        state.write("kind\tseconds\tstate\tsong\tplace\tconfidence\tms\trmsDb\tpeakDb\tclipped\twall")
    }
    let wall0 = Date()
    let booth = BoothRecogniser(index: index) { r in
        state.lock.lock(); state.reading = r; state.lock.unlock()
        state.write(String(format: "reading\t%.1f\t%@\t%@\t%@\t%.2f\t%.0f\t\t\t\t%.2f", r.time, r.state.rawValue, r.id ?? "-",
                           r.positionSeconds.map { String(format: "%.1f", $0) } ?? "-", r.confidence, r.milliseconds,
                           Date().timeIntervalSince(wall0)))
    }
    let capture = LiveCapture(source)
    let format: SoundFormat
    do {
        format = try capture.start(sound: { samples, f in booth.feed(samples, channels: f.channels, sampleRate: f.rate) },
                                   level: { l in
                                       state.lock.lock(); state.level = l; state.clippedSince += l.clipped; state.lock.unlock()
                                       state.write(String(format: "level\t%.2f\t\t\t\t\t\t%.1f\t%.1f\t%d\t%.2f", l.seconds, l.rmsDB, l.peakDB, l.clipped,
                                                          Date().timeIntervalSince(wall0)))
                                   },
                                   ended: { e in state.lock.lock(); state.ended = e; state.lock.unlock() })
    } catch { liveFail("cannot open the input: \(error)") }
    FileHandle.standardError.write(Data("listening to \(source.name) at \(format.rate) Hz, \(format.channels) channel(s); Ctrl+C stops\n".utf8))
    print("seconds\tlevel dB\tpeak dB\tclipped\tsong\tplace\tsure\tms")
    let stopAfter = Double(values["--seconds"] ?? "") ?? .infinity
    signal(SIGINT) { _ in exit(0) }
    while true {
        Thread.sleep(forTimeInterval: 1)
        state.lock.lock()
        let l = state.level, r = state.reading, e = state.ended, clipped = state.clippedSince
        state.clippedSince = 0
        state.lock.unlock()
        if let e { capture.stop(); liveFail("the input stopped: \(e)") }
        let song = r.flatMap { $0.state == .nothingYet ? nil : $0.id }
        let place = r?.positionSeconds.map { String(format: "%d:%02d", Int($0) / 60, Int($0) % 60) } ?? "-"
        print(String(format: "%.0f\t%.1f\t%.1f\t%d\t%@\t%@\t%.1f\t%.0f", l?.seconds ?? 0, l?.rmsDB ?? -120, l?.peakDB ?? -120, clipped,
                     song.map { names[$0] ?? $0 } ?? (l?.silent == true ? "- (no sound arriving)" : "-"),
                     song == nil ? "-" : place, song == nil ? 0 : (r?.confidence ?? 0), r?.milliseconds ?? 0))
        fflush(stdout)
        if (l?.seconds ?? 0) >= stopAfter || Date().timeIntervalSince(wall0) > stopAfter + 30 { break }
    }
    capture.stop()
    booth.finish()
    exit(0)
}
