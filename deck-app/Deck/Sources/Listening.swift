import AVFoundation
import Darwin
import Foundation
import ShazamKit
import DeckieCrate
import DeckieRecognition

// The booth's two recognisers behind one small interface (D35). Each turns the sound it hears into readings; the
// Recognizer (`take`) is the one place a reading becomes the playing song, the pitch shown and the set's log. Nothing
// leaves the iPad with either: Deckie's matches against an index made from the crate file's fingerprints, Apple's
// against a catalogue made from the crate file's signatures (or the bundled one), both on the iPad.

/// Which recogniser names the playing song: Deckie's own, Apple's, or both at once (Deckie's on screen, the two
/// compared in the set's log).
enum Hearing: String, CaseIterable, Identifiable {
    case deckie, apple, both
    var id: String { rawValue }
    /// The DJ's choice, remembered; Deckie's unless another was chosen.
    static var chosen: Hearing {
        get { UserDefaults.standard.string(forKey: "hearing").flatMap(Hearing.init(rawValue:)) ?? .deckie }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "hearing") }
    }
}

/// One recogniser's word on what is playing.
struct Reading {
    enum From: String { case deckie, apple }
    var from: From
    /// When the sound it is about was heard, and how many seconds of sound had been heard by then.
    var date: Date
    var audioTime: Double
    /// The song (a crate entry's id); nil when nothing is named.
    var id: String?
    /// Seconds into the song as recorded, at `date`.
    var position: Double?
    /// The deck's speed read from this listen, in percent (nil: this recogniser reads it only over time, from how
    /// fast the place moves).
    var speedPercent: Double?
    /// Whether the key held while the speed moved (true), moved with it (false), or cannot be told (nil).
    var keyLock: Bool?
    /// How far the key has moved, as a ratio (1: not at all).
    var pitchRatio = 1.0
    /// Apple's tempo-only catalogue variant: a speed in percent that stands in until it is measured.
    var speedHint: Double?
    /// How the speed was found, for the details sheet.
    var speedFrom = ""
    /// The recogniser's own confidence (Deckie: its standing, 3 and more sure; Apple: 1 for a match).
    var confidence = 1.0
    /// Whether the recogniser checked this place against the song itself (Deckie follows a song on its line), so a
    /// jump to another place in the song is taken at once rather than after the wait a repeated chorus needs.
    var vouched = false
    /// Named by a search of the crate (not a song only followed).
    var fresh = true
    /// How long the reading took to work out.
    var milliseconds: Double?
    /// Deckie's: how many more readings naming this song the booth waits for before it replaces the song on screen
    /// (0: at once). Nil for Apple's, whose readings keep the hold written for them (`Recognizer.take`).
    var wait: Int?
    /// The song heard coming in under the one playing, when the recogniser reports one (the next version of Deckie's
    /// listener will; nothing fills it yet). The booth carries it as `Recognizer.incoming`.
    var incoming: Incoming?

    /// A second song heard under the playing one: the song (a crate entry's id), its place, its speed, how sure.
    struct Incoming: Equatable {
        var id: String
        var position: Double?
        var speedPercent: Double?
        var keyLock: Bool?
        var confidence: Double
    }
}

/// Hears the booth's sound: one buffer at a time, from the microphone tap or a test file. Called off the main thread.
protocol Ear: AnyObject, Sendable {
    func hear(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime?)
    func stop()
}

/// Apple's recogniser: the buffers go to a ShazamKit session; its results are read on the main actor by the
/// Recognizer, which makes readings of them (`appleReading`).
final class AppleEar: Ear, @unchecked Sendable {
    let session: SHSession
    init(catalog: SHCustomCatalog) { session = SHSession(catalog: catalog) }
    func hear(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime?) { session.matchStreamingBuffer(buffer, at: time) }
    func stop() {}
}

/// Deckie's recogniser: the buffers, made mono, go to the core's `BoothRecogniser`, which returns at once and reads on
/// a thread of its own about once a second. Each reading is handed to `onReading` on the main actor. The listener
/// itself follows a named song cheaply and searches the whole crate every other second; nothing here restarts or
/// searches on its own.
final class DeckieEar: Ear, @unchecked Sendable {
    private var booth: BoothRecogniser!
    private let lock = NSLock()
    private var stopped = false

    init(index: RecognitionIndex, onReading: @escaping @MainActor (ListenReading, Date) -> Void) {
        booth = BoothRecogniser(index: index) { [weak self] reading in
            // On the recogniser's thread: whatever Foundation sets aside here is released at once (pooled).
            pooled {
                guard let self, !self.isStopped else { return }
                // The sound this reading is about ended `milliseconds` ago.
                let heard = Date().addingTimeInterval(-reading.milliseconds / 1000)
                DispatchQueue.main.async { MainActor.assumeIsolated { onReading(reading, heard) } }
            }
        }
    }
    private var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }

    /// From the audio thread: the buffer's channels mixed to one, at whatever rate it arrives, handed over; the
    /// recogniser copies it and returns.
    func hear(_ buffer: AVAudioPCMBuffer, at time: AVAudioTime?) {
        guard !isStopped, let data = buffer.floatChannelData else { return }
        let n = Int(buffer.frameLength), ch = Int(buffer.format.channelCount)
        guard n > 0, ch > 0 else { return }
        pooled {
            var mono = [Float](repeating: 0, count: n)
            mono.withUnsafeMutableBufferPointer { out in
                for c in 0..<ch {
                    let src = data[c]
                    for i in 0..<n { out[i] += src[i] }
                }
                if ch > 1 { let k = 1 / Float(ch); for i in 0..<n { out[i] *= k } }
            }
            booth.feed(mono, sampleRate: Int(buffer.format.sampleRate.rounded()))
        }
    }

    func stop() { lock.lock(); stopped = true; lock.unlock() }
}

/// Deckie's index for the open crate file: built once from its fingerprints (off the main thread), kept beside the
/// app's copy of the crate file with the core's stamp, and opened in place (mapped) every time after.
@MainActor @Observable final class DeckieIndex {
    enum State: Equatable { case none, preparing(songs: Int), ready, failed(String) }
    private(set) var state: State = .none
    private(set) var index: RecognitionIndex?
    /// Seconds the last preparation took, and whether it built the index or opened a kept one.
    private(set) var seconds = 0.0
    private(set) var built = false
    private var generation = 0
    private var waiting: [() -> Void] = []

    /// The setting the index is made with: `booth` (the default), or `boothSmall` when the launch argument
    /// `-indexSmall YES` is given (for measuring).
    static var pairing: PairingConfig { UserDefaults.standard.bool(forKey: "indexSmall") ? .boothSmall : .booth }
    static var settingName: String { UserDefaults.standard.bool(forKey: "indexSmall") ? "boothSmall" : "booth" }

    /// Where the index of the crate file kept at `package` lives: beside it, in the app's own storage.
    static func file(for package: URL) -> URL {
        package.deletingPathExtension().appendingPathExtension("recognition.dkx")
    }

    /// Starts making ready the index for these fingerprints (nil: the crate file has none).
    func prepare(_ prints: Crate.Fingerprints?, package: URL?, note: @escaping (String) -> Void) {
        generation += 1
        let mine = generation
        index = nil; waiting = []
        guard let prints, prints.count > 0, let package else { state = .none; return }
        state = .preparing(songs: prints.count)
        let url = Self.file(for: package), pairing = Self.pairing, name = Self.settingName
        let before = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
        let t0 = Date()
        Task.detached(priority: .userInitiated) {
            let result: Result<RecognitionIndex, Error> = pooled { Result { try prints.songs().index(cachedAt: url, pairing: pairing) } }
            await MainActor.run {
                guard self.generation == mine else { return }
                self.seconds = Date().timeIntervalSince(t0)
                switch result {
                case .success(let ix):
                    self.index = ix; self.state = .ready
                    let file = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? ix.fileBytes
                    let after = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
                    self.built = before == nil || after != before
                    note(String(format: "Deckie's index (%@): %d songs, %.1f MB on disk (%.1f KB a song), %@ in %.1f s; app memory %.0f MB",
                                name, ix.songCount, Double(file) / 1e6, Double(file) / 1e3 / Double(max(1, ix.songCount)),
                                self.built ? "built from the fingerprints" : "opened in place", self.seconds, appMemoryMB()))
                    let w = self.waiting; self.waiting = []
                    w.forEach { $0() }
                case .failure(let e):
                    self.state = .failed("\(e)")
                    note("Deckie's index failed: \(e)")
                    self.waiting = []
                }
            }
        }
    }

    /// Runs `then` once the index is ready (at once if it is).
    func whenReady(_ then: @escaping () -> Void) {
        if state == .ready { then() } else if case .preparing = state { waiting = [then] }
    }

    func forget() { generation += 1; index = nil; state = .none; waiting = [] }
}

/// The app's memory as the system counts it against the app (its footprint), in MB.
func appMemoryMB() -> Double {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
    let kr = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count) }
    }
    return kr == KERN_SUCCESS ? Double(info.phys_footprint) / 1e6 : 0
}

/// The deck's speed from how fast a song's place moves against the sound heard: the median of the slopes between
/// every two readings at least 3 s apart (Theil-Sen, so one stray reading cannot pull it), from 12 s and three
/// readings on (track H measured two matches 8 s apart to a few hundredths; in the app the first 10 s read rough).
/// Nil before that, or when the slope is not a deck's.
func speedFromPlaces(_ points: [(audioTime: Double, offset: Double)]) -> (ratio: Double, span: Double)? {
    guard let f = points.first, let l = points.last, points.count >= 3, l.audioTime - f.audioTime >= 12 else { return nil }
    var slopes: [Double] = []
    for i in 0..<points.count { for j in (i + 1)..<points.count {
        let dt = points[j].audioTime - points[i].audioTime
        if dt >= 3 { slopes.append((points[j].offset - points[i].offset) / dt) }
    } }
    slopes.sort()
    guard !slopes.isEmpty else { return nil }
    let slope = slopes[slopes.count / 2]
    return slope > 0.8 && slope < 1.2 ? (slope, l.audioTime - f.audioTime) : nil
}

/// Compare mode: what each recogniser named, when, and at what speed, song by song, and where they disagreed. Kept
/// for the set and written to the set's log, so the two can be judged on a real night.
@MainActor @Observable final class Comparison {
    struct Song: Codable {
        var id: String
        var title: String
        /// Seconds into the set (the recording's clock) when each first named this song in this play of it.
        var deckieFirst: Double?
        var appleFirst: Double?
        /// ...and when each last named it.
        var deckieLast: Double?
        var appleLast: Double?
        /// The deck's speed each read for it, in percent: Deckie's median reading; Apple's from its key's skew
        /// (vinyl) or from how fast its place moved.
        var deckieSpeed: Double?
        var appleSpeed: Double?
        var deckieKeyLock: Bool?
        var deckieReadings = 0
        var appleMatches = 0
    }
    /// A moment the two named different songs. `atChange`: each recogniser named the other's song too, within
    /// `changeWindow` seconds of that moment (or was naming it then), so it was one song giving way to the next, heard
    /// by one before the other (a blend), not a wrong name.
    struct Disagreement: Codable { var at: Double; var deckie: String; var apple: String; var atChange: Bool? = nil }
    struct Log: Codable {
        var songs: [Song]
        var disagreements: [Disagreement]
        var summary: String
    }

    private(set) var songs: [Song] = []
    private(set) var disagreements: [Disagreement] = []
    private var open: [String: Int] = [:]                 // a song's recording key -> its row in `songs`
    private var lastNamed: [String: Double] = [:]          // the recording key -> the last time either named it
    private var last: [Reading.From: (time: Double, key: String, id: String)] = [:]
    private var deckieSpeeds: [Int: [Double]] = [:]
    private var applePlaces: [Int: [(audioTime: Double, offset: Double)]] = [:]
    private var appleSkews: [Int: [Double]] = [:]
    /// A song not named by either for this long is played again the next time it is named.
    static let newPlay = 120.0
    /// Two readings this close in time are about the same moment; a disagreement within this of the last one about
    /// the same two songs is the same disagreement.
    static let sameMoment = 3.0, sameDisagreement = 15.0, changeWindow = 30.0

    func reset() { songs = []; disagreements = []; open = [:]; lastNamed = [:]; last = [:]; deckieSpeeds = [:]; applePlaces = [:]; appleSkews = [:] }

    /// A reading that names a song. `t` is seconds into the set. Returns whether the log has something new.
    @discardableResult
    func heard(_ r: Reading, at t: Double) -> Bool {
        guard let id = r.id, let track = Library.shared.track(id) else { return false }
        let key = track.cut
        var changed = false
        if let seen = lastNamed[key], t - seen > Self.newPlay { open[key] = nil }
        lastNamed[key] = t
        let row: Int
        if let k = open[key] { row = k } else {
            row = songs.count; open[key] = row
            songs.append(Song(id: id, title: track.oneLine)); changed = true
        }
        switch r.from {
        case .deckie:
            if songs[row].deckieFirst == nil { songs[row].deckieFirst = (t * 10).rounded() / 10; changed = true }
            songs[row].deckieReadings += 1
            songs[row].deckieLast = (t * 10).rounded() / 10
            if let s = r.speedPercent { deckieSpeeds[row, default: []].append(s) }
            let s = (deckieSpeeds[row] ?? []).sorted()
            if !s.isEmpty { songs[row].deckieSpeed = (s[s.count / 2] * 100).rounded() / 100 }
            if r.keyLock != nil { songs[row].deckieKeyLock = r.keyLock }
        case .apple:
            if songs[row].appleFirst == nil { songs[row].appleFirst = (t * 10).rounded() / 10; changed = true }
            songs[row].appleMatches += 1
            songs[row].appleLast = (t * 10).rounded() / 10
            if abs(r.pitchRatio - 1) > 0.008 { appleSkews[row, default: []].append((r.pitchRatio - 1) * 100) }
            if let p = r.position { applePlaces[row, default: []].append((r.audioTime, p)); applePlaces[row] = Array(applePlaces[row]!.suffix(12)) }
            if let k = appleSkews[row], !k.isEmpty {
                songs[row].appleSpeed = ((k.suffix(4).reduce(0, +) / Double(k.suffix(4).count)) * 100).rounded() / 100
            } else if let fit = speedFromPlaces(applePlaces[row] ?? []) {
                songs[row].appleSpeed = ((fit.ratio - 1) * 10000).rounded() / 100
            } else if let h = r.speedHint { songs[row].appleSpeed = h }
        }
        // A disagreement: the other recogniser named another recording at about the same moment.
        let other: Reading.From = r.from == .deckie ? .apple : .deckie
        if let o = last[other], t - o.time <= Self.sameMoment, o.key != key {
            let (d, a) = r.from == .deckie ? (id, o.id) : (o.id, id)
            let same = disagreements.last.map { t - $0.at <= Self.sameDisagreement && Library.shared.sameSong($0.deckie, d) && Library.shared.sameSong($0.apple, a) } ?? false
            if !same {
                disagreements.append(Disagreement(at: (t * 10).rounded() / 10, deckie: d, apple: a)); changed = true
            }
        }
        last[r.from] = (t, key, id)
        return changed
    }

    /// The counts the summary gives: songs each named; of the songs both named, which named it first (a tie, to the
    /// tenth of a second, counts for neither); and the disagreements.
    var counts: (deckie: Int, apple: Int, deckieFirst: Int, appleFirst: Int, disagreed: Int) {
        let d = songs.filter { $0.deckieFirst != nil }.count, a = songs.filter { $0.appleFirst != nil }.count
        var df = 0, af = 0
        for s in songs {
            switch (s.deckieFirst, s.appleFirst) {
            case let (x?, y?): if x < y { df += 1 } else if y < x { af += 1 }
            default: break      // named by one only: counted in its total, not as first
            }
        }
        return (d, a, df, af, disagreements.count)
    }

    /// The disagreements, each marked whether it came at a song change.
    var markedDisagreements: [Disagreement] {
        disagreements.map { x in
            var y = x
            // Whether the recogniser named this song near the moment: its first and last namings of it bracket the
            // moment, give or take `changeWindow`.
            let near = { (id: String, first: (Song) -> Double?, last: (Song) -> Double?) in
                self.songs.contains { s in
                    guard Library.shared.sameSong(s.id, id), let a = first(s), let b = last(s) else { return false }
                    return a - Self.changeWindow <= x.at && x.at <= b + Self.changeWindow
                }
            }
            y.atChange = near(x.apple, { $0.deckieFirst }, { $0.deckieLast }) && near(x.deckie, { $0.appleFirst }, { $0.appleLast })
            return y
        }
    }

    var summary: String {
        let c = counts
        return Words.compareSummary(deckie: c.deckie, apple: c.apple, deckieFirst: c.deckieFirst, appleFirst: c.appleFirst, disagreed: c.disagreed,
                                    atChange: markedDisagreements.filter { $0.atChange == true }.count)
    }
    var log: Log { Log(songs: songs, disagreements: markedDisagreements, summary: summary) }
}
