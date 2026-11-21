import Foundation
@testable import DeckieRecognition

/// What the golden tests feed a switching rule, one step at a time, on a clock of their own.
enum RuleStep {
    /// One of Deckie's readings (`ListenReading`), at seconds `t` of the set; the rule takes it `ms` later.
    case deckie(t: Double, ListenReading)
    /// A reading as the rule takes it (Apple's, or one carrying a song coming in), at seconds `t`.
    case reading(t: Double, PresentReading)
    /// The once-a-second check (pauses, "not heard", the two-minute rule), at seconds `t`.
    case tick(t: Double)
    /// The input's level from now on, in dB.
    case level(Float)
    /// The song set by hand at seconds `t`.
    case manual(t: Double, id: String)
    /// Another crate file opened.
    case forget
    /// Listening started again from the microphone at seconds `t` (after a song set by hand).
    case listen(t: Double)
}

/// A rule the steps can drive: the present one (PresentRule) or the shared one, with what the screen shows after each
/// step written as one line.
protocol RuleUnderTest: AnyObject {
    func apply(_ step: RuleStep)
    /// What the screen shows at `t`.
    func line(at t: Double) -> String
}

let ruleEpoch = Date(timeIntervalSince1970: 1_800_000_000)
func at(_ t: Double) -> Date { ruleEpoch.addingTimeInterval(t) }

/// The golden text for one script: a line per step.
func runScript(_ rule: RuleUnderTest, _ name: String, _ steps: [RuleStep]) -> String {
    var out = ["# \(name)"]
    var t = 0.0
    for (i, s) in steps.enumerated() {
        rule.apply(s)
        switch s {
        case let .deckie(x, r): t = x + r.milliseconds / 1000
        case let .reading(x, r): t = x + (r.milliseconds ?? 0) / 1000
        case let .tick(x): t = x
        case let .manual(x, _): t = x
        case let .listen(x): t = x
        case .level, .forget: break
        }
        out.append("\(i) \(stepName(s)) | \(rule.line(at: t))")
    }
    return out.joined(separator: "\n")
}

func stepName(_ s: RuleStep) -> String {
    switch s {
    case let .deckie(t, r):
        return "deckie t=\(t) \(r.state.rawValue) \(r.id ?? "-") pos=\(r.positionSeconds.map { "\($0)" } ?? "-") conf=\(r.confidence) agrees=\(r.searched.map { "\($0.agrees)" } ?? "-")"
    case let .reading(t, r): return "reading t=\(t) \(r.from.rawValue) \(r.id ?? "-") wait=\(r.wait.map { "\($0)" } ?? "-")"
    case let .tick(t): return "tick t=\(t)"
    case let .level(l): return "level \(l)"
    case let .manual(t, id): return "manual t=\(t) \(id)"
    case .forget: return "forget"
    case let .listen(t): return "listen t=\(t)"
    }
}

// MARK: readings

func named(_ t: Double, _ id: String, pos: Double, speed: Double = 0, keyLock: Bool? = nil, conf: Double = 4, agrees: Bool = false,
           ms: Double = 60) -> RuleStep {
    .deckie(t: t, ListenReading(time: t, state: .named, songIndex: 0, id: id, positionSeconds: pos, speedPercent: speed, keyLock: keyLock,
                                confidence: conf, milliseconds: ms,
                                searched: .init(id: id, confidence: conf, agrees: agrees)))
}
func held(_ t: Double, _ id: String, pos: Double, speed: Double = 0, keyLock: Bool? = nil, conf: Double = 40, ms: Double = 20,
          searched: ListenReading.Searched? = nil) -> RuleStep {
    .deckie(t: t, ListenReading(time: t, state: .held, songIndex: 0, id: id, positionSeconds: pos, speedPercent: speed, keyLock: keyLock,
                                confidence: conf, milliseconds: ms, searched: searched))
}
func nothing(_ t: Double, ms: Double = 80) -> RuleStep {
    .deckie(t: t, ListenReading(time: t, state: .nothingYet, songIndex: nil, id: nil, positionSeconds: nil, speedPercent: nil,
                                keyLock: nil, confidence: 0, milliseconds: ms, searched: nil))
}
func apple(_ t: Double, _ id: String?, pos: Double?, ratio: Double = 1, hint: Double? = nil, from: String = "frequency skew",
           ms: Double = 900) -> RuleStep {
    .reading(t: t, PresentReading(from: .apple, date: at(t), audioTime: t, id: id, position: pos, speedPercent: nil,
                                  keyLock: abs(ratio - 1) > 0.008 ? false : nil, pitchRatio: ratio, speedHint: hint,
                                  speedFrom: id == nil ? "" : from, milliseconds: id == nil ? nil : ms))
}

/// A song followed for seconds `from...to`: named at the start (sure), held after, with a deck speed that wobbles a
/// little, ticks in between.
func follow(_ id: String, _ from: Int, _ to: Int, start: Double, speed: Double = 0, keyLock: Bool? = nil, conf: Double = 40,
            namedFirst: Bool = true) -> [RuleStep] {
    var s: [RuleStep] = []
    for i in from...to {
        let t = Double(i)
        let wob = 0.1 * sin(t * 1.7)
        let pos = start + (t - Double(from)) * (1 + speed / 100)
        if i == from && namedFirst { s.append(named(t, id, pos: pos, speed: speed + wob, keyLock: keyLock)) }
        else { s.append(held(t, id, pos: pos, speed: speed + wob, keyLock: keyLock, conf: conf + 5 * sin(t))) }
        s.append(.tick(t: t + 0.5))
    }
    return s
}

// MARK: the hand-made scripts

enum RuleScripts {
    static let A = "s01", B = "s02", C = "s03"

    static var handMade: [(String, [RuleStep])] {
        var out: [(String, [RuleStep])] = []

        out.append(("steady song", follow(A, 3, 60, start: 30, speed: 2)))

        out.append(("hard cut", follow(A, 3, 40, start: 10) + follow(B, 41, 70, start: 0, speed: -1.5)))

        // A gives way to B, then A is named again within the return window: the careful wait.
        out.append(("quick return", follow(A, 3, 30, start: 60) + follow(B, 31, 40, start: 5)
                    + [named(41, A, pos: 101), .tick(t: 41.5), held(42, A, pos: 102), .tick(t: 42.5), held(43, A, pos: 103),
                       .tick(t: 43.5), held(44, A, pos: 104), .tick(t: 44.5)] + follow(A, 45, 55, start: 105, namedFirst: false)))

        // A blend: B comes in under A; B's followed readings are no stronger than A's a moment before (dominance), then
        // B takes over.
        var blend = follow(A, 3, 40, start: 100, conf: 30)
        for i in 41...60 {
            let t = Double(i)
            if i % 2 == 1 { blend.append(held(t, A, pos: 100 + t - 3, conf: 25)) }
            else if i % 4 == 0 { blend.append(named(t, B, pos: t - 40, conf: 2.8, agrees: i % 8 == 0)) }
            else { blend.append(held(t, B, pos: t - 40, conf: 20)) }
            blend.append(.tick(t: t + 0.5))
        }
        blend += follow(B, 61, 80, start: 21, conf: 45, namedFirst: false)
        out.append(("blend, two songs trading places", blend))

        // A wrong name flickers in: once named and sure, once only followed and weak.
        out.append(("wrong name flickering in", follow(A, 3, 30, start: 0)
                    + [named(31, C, pos: 80), .tick(t: 31.5)] + follow(A, 32, 40, start: 29, namedFirst: false)
                    + [held(41, C, pos: 90, conf: 10), .tick(t: 41.5)] + follow(A, 42, 50, start: 39, namedFirst: false)
                    + [named(51, C, pos: 80, conf: 2.7), .tick(t: 51.5), named(52, C, pos: 81, conf: 2.7, agrees: true), .tick(t: 52.5)]
                    + follow(A, 53, 60, start: 50, namedFirst: false)))

        // A new song named only fairly, again and again (the fair wait), then sure and agreeing (no wait at all).
        var fair = follow(A, 3, 20, start: 0)
        for i in 21...26 { fair.append(named(Double(i), B, pos: Double(i) - 21, conf: 2.8, agrees: true)); fair.append(.tick(t: Double(i) + 0.5)) }
        fair += follow(B, 27, 35, start: 6, namedFirst: false)
        for i in 36...38 { fair.append(named(Double(i), C, pos: Double(i), conf: 3.5, agrees: true)); fair.append(.tick(t: Double(i) + 0.5)) }
        // The song before, back after the return window has passed: the plain wait.
        fair += follow(C, 39, 70, start: 39, namedFirst: false) + [named(71, B, pos: 50), .tick(t: 71.5)] + follow(B, 72, 74, start: 51, namedFirst: false)
        out.append(("a fair name, again and again", fair))

        // Silence: the song is not heard, the room goes quiet (paused), and after two minutes the screen lets go.
        var silence = follow(A, 3, 20, start: 40, speed: 1)
        silence.append(.level(-60))
        for i in 21...170 { silence.append(nothing(Double(i))); silence.append(.tick(t: Double(i) + 0.5)) }
        silence.append(.level(-18))
        silence += follow(A, 171, 180, start: 90)
        out.append(("silence", silence))

        // A quiet room just under the line (-48 dB): paused, a reading from sound buffered before the pause set aside,
        // then the music back.
        var hush = follow(A, 3, 15, start: 20)
        hush.append(.level(-48))
        for i in 16...24 { hush.append(nothing(Double(i))); hush.append(.tick(t: Double(i) + 0.5)) }
        hush += [held(25, A, pos: 33), .tick(t: 25.5), .level(-43), nothing(26), .tick(t: 26.5), .level(-20)]
        hush += follow(A, 27, 32, start: 34, namedFirst: false)
        out.append(("a quiet room", hush))

        // Talk over the music: not heard, the room not quiet, then heard again at the place it should be.
        var talk = follow(A, 3, 20, start: 40)
        for i in 21...28 { talk.append(nothing(Double(i))); talk.append(.tick(t: Double(i) + 0.5)) }
        talk += follow(A, 29, 35, start: 66, namedFirst: false)
        out.append(("not heard just now", talk))

        out.append(("a song not in the crate", follow("zz", 3, 15, start: 0) + follow(B, 16, 30, start: 0)
                    + follow("zz", 31, 40, start: 20)))

        // Copies (D24) and places (D27): a copy of the playing song is the playing song; another song is its leading
        // copy.
        out.append(("copies and places", follow("s07", 3, 20, start: 0) + follow("s06", 21, 40, start: 0)
                    + follow("s05", 41, 50, start: 20, namedFirst: false) + follow("s05", 51, 60, start: 0)
                    + follow("s07", 61, 70, start: 0)))

        // The fader: a steady speed, one stray reading set aside, then a move shown from two readings.
        var fader: [RuleStep] = []
        for i in 3...40 {
            let t = Double(i)
            let s = i < 15 ? 2.0 : i == 15 ? 7.6 : i < 25 ? 2.05 : 3.2 + 0.02 * Double(i % 3)
            fader.append(i == 3 ? named(t, A, pos: t, speed: s, keyLock: true) : held(t, A, pos: t, speed: s, keyLock: i < 30 ? true : false))
            fader.append(.tick(t: t + 0.5))
        }
        out.append(("fader moves", fader))

        // Jumps within the song: Deckie's vouched jump is taken at once.
        out.append(("place jumps", follow(A, 3, 20, start: 0) + follow(A, 21, 30, start: 100, namedFirst: false)
                    + follow(A, 31, 40, start: 8, namedFirst: false)))

        // Set by hand, then the microphone hears another song: the careful wait.
        out.append(("set by hand", [.manual(t: 1, id: "s04"), .tick(t: 2), .tick(t: 3), .listen(t: 4)]
                    + follow(A, 5, 12, start: 0) + [.manual(t: 13, id: "s24"), .listen(t: 14)] + follow("s24", 15, 20, start: 50)))

        // Apple's readings: the hold, a blend, a hard cut, a restart, a repeated section, vinyl and drift.
        var ap: [RuleStep] = []
        for i in stride(from: 4, through: 60, by: 4) { ap.append(apple(Double(i), A, pos: 30 + Double(i) * 1.04)); ap.append(.tick(t: Double(i) + 0.5)) }
        for i in stride(from: 62, through: 90, by: 2) {
            let t = Double(i)
            ap.append(apple(t, i % 4 == 0 ? A : B, pos: i % 4 == 0 ? 30 + t * 1.04 : t - 60))
            ap.append(.tick(t: t + 0.5))
        }
        for i in stride(from: 92, through: 120, by: 3) { ap.append(apple(Double(i), B, pos: Double(i) - 60, ratio: 1.03)); ap.append(.tick(t: Double(i) + 0.5)) }
        ap.append(apple(121, nil, pos: nil))
        for i in stride(from: 125, through: 150, by: 3) { ap.append(apple(Double(i), C, pos: Double(i) - 125, hint: 4, from: "tempo-only variant")) }
        ap += [apple(153, C, pos: 5), apple(156, C, pos: 8), apple(159, C, pos: 80), apple(162, C, pos: 83), apple(168, C, pos: 89),
               apple(171, C, pos: 92), apple(180, C, pos: 101), .tick(t: 181), apple(185, C, pos: 3), apple(188, C, pos: 6)]
        out.append(("Apple's readings", ap))

        // A song coming in (the listener will report one; the rule carries it as its leading copy).
        var inc: [RuleStep] = follow(A, 3, 10, start: 0)
        for i in 11...16 {
            let t = Double(i)
            inc.append(.reading(t: t, PresentReading(from: .deckie, date: at(t), audioTime: t, id: A, position: t - 3, speedPercent: 0,
                                                     keyLock: nil, pitchRatio: 1, speedFrom: "Deckie's reading", confidence: 30,
                                                     vouched: true, fresh: false, milliseconds: 20, wait: 1,
                                                     incoming: .init(id: i < 14 ? "s06" : A, position: t - 11, speedPercent: 0.5,
                                                                     keyLock: nil, confidence: 2))))
        }
        inc += follow("s05", 17, 25, start: 6)
        out.append(("a song coming in", inc))

        out.append(("another crate opened", follow(A, 3, 10, start: 0) + follow(B, 11, 20, start: 0) + [.forget] + follow(C, 21, 30, start: 0)))
        return out
    }

    /// Generated sets: songs played one after another with blends, wrong names, gaps, silences, fader moves and the
    /// listener's own delays, from a seeded generator.
    static func generated(_ seed: UInt64, seconds: Int = 300) -> [RuleStep] {
        var rng = SeededRNG(seed: seed)
        func u() -> Double { Double.random(in: 0..<1, using: &rng) }
        let pool = ["s01", "s02", "s03", "s05", "s06", "s07", "s16", "s17", "s18", "zz"]
        var steps: [RuleStep] = []
        var song = pool[Int(u() * Double(pool.count))]
        var place = u() * 100, speed = (u() - 0.5) * 8
        var next = 20 + Int(u() * 40)
        var quiet = false
        var lastSong: String?
        let appleRun = seed % 4 == 3
        for i in 3...seconds {
            let t = Double(i)
            place += 1 + speed / 100
            if i == next {
                lastSong = song
                song = pool[Int(u() * Double(pool.count))]; place = u() * 30; next = i + 15 + Int(u() * 45)
                if u() < 0.3 { speed = (u() - 0.5) * 8 }
            }
            if u() < 0.02 { quiet.toggle(); steps.append(.level(quiet ? -60 : -20)) }
            if u() < 0.03 { speed += (u() - 0.5) * 3 }
            if u() < 0.01 { place += (u() - 0.5) * 120 }
            let ms = 15 + u() * 300
            if appleRun {
                if i % 3 == 0 {
                    let x = u()
                    if quiet || x < 0.2 { steps.append(apple(t, nil, pos: nil)) }
                    else if x < 0.3, let l = lastSong { steps.append(apple(t, l, pos: place + 40, ratio: 1 + speed / 100, ms: ms * 3)) }
                    else { steps.append(apple(t, song, pos: place, ratio: x < 0.6 ? 1 + speed / 100 : 1, hint: x > 0.9 ? 4 : nil, ms: ms * 3)) }
                }
            } else {
                let x = u()
                if quiet || x < 0.08 { steps.append(nothing(t, ms: ms)) }
                else if x < 0.12 { steps.append(named(t, pool[Int(u() * Double(pool.count))], pos: u() * 200, speed: speed, conf: 2.6 + u() * 3, ms: ms)) }
                else if x < 0.2, let l = lastSong, i - next < 60 { steps.append(held(t, l, pos: place + 40, speed: speed, conf: u() * 40, ms: ms)) }
                else if x < 0.3 { steps.append(named(t, song, pos: place, speed: speed + (u() - 0.5) * 0.4, keyLock: speed > 0, conf: 2.6 + u() * 4, agrees: u() < 0.5, ms: ms)) }
                else { steps.append(held(t, song, pos: place, speed: speed + (u() - 0.5) * 0.4, keyLock: speed > 0 ? true : nil, conf: u() * 60, ms: ms)) }
            }
            if u() < 0.01 { steps.append(.manual(t: t + 0.2, id: pool[Int(u() * 9)])); steps.append(.listen(t: t + 0.3)) }
            steps.append(.tick(t: t + 0.5))
        }
        return steps
    }

    static let seeds: [UInt64] = Array(1...12)
}

// MARK: the present rule, driven

final class PresentDriver: RuleUnderTest {
    let rule: PresentRule
    var now = ruleEpoch
    init(_ lib: PresentLibrary) {
        var clockNow = ruleEpoch
        rule = PresentRule(lib: lib, clock: { clockNow })
        setClock = { clockNow = $0 }
        rule.startedAt = ruleEpoch
    }
    private var setClock: (Date) -> Void = { _ in }

    func apply(_ step: RuleStep) {
        rule.shownNewSong = false
        switch step {
        case let .deckie(t, r):
            // In the app: `heard` is the moment the sound ended (now less the reading's milliseconds); `take` runs now.
            setClock(at(t + r.milliseconds / 1000))
            rule.deckieReading(r, heard: at(t))
        case let .reading(t, r):
            setClock(at(t + (r.milliseconds ?? 0) / 1000))
            rule.take(r)
        case let .tick(t):
            setClock(at(t)); rule.tick()
        case let .level(l): rule.inputLevel = l
        case let .manual(t, id):
            setClock(at(t)); rule.setManual(id)
        case .forget: rule.forgetSongs(); rule.source = .mic
        case let .listen(t):
            setClock(at(t)); rule.source = .mic; rule.startedAt = at(t); rule.status = "listening…"
        }
    }

    func line(at t: Double) -> String {
        let r = rule
        let notes = r.notes; r.notes = []
        let place = r.currentPlace.map { "\($0.disc ?? "-")/\($0.folder)/\($0.num.map { "\($0)" } ?? "-")" } ?? "-"
        let inc = r.incoming.map { "\($0.id)@\($0.position.map { "\($0)" } ?? "-")" } ?? "-"
        return "cur=\(r.currentId ?? "-") place=\(place) known=\(r.positionKnown) anchor=\(r.anchorOffset)@\(r.anchorDate.timeIntervalSince(ruleEpoch))"
            + " rate=\(r.rate) pitch=\(r.pitchPct) kind=\(r.pitchKind.rawValue) from=\(r.pitchFrom) notHeard=\(r.notHeard) paused=\(r.paused)"
            + " also=\(r.alsoHearing ?? "-") incoming=\(inc) history=\(r.history.joined(separator: ","))"
            + " first=\(r.firstMatchSeconds.map { "\($0)" } ?? "-") conf=\(r.confidence) pos=\(r.position(at: at(t)))"
            + " matches=\(r.matchCount) none=\(r.noMatchCount) new=\(r.shownNewSong) status=\(r.status)"
            + (notes.isEmpty ? "" : " notes=[\(notes.joined(separator: " ; "))]")
    }
}
