import SwiftUI
import AppKit
import DeckieDesk

// The run screen on the Mac (D37): the same screen as the Windows and Linux window's (desk-web/run.js), from the same
// data, which the Mac gets from DeskRun directly (RunProgress's song, notes and figures). Everything drawn is a song
// Desk read; every number is counted by the core; every sentence is one the core said is true, or a line about the
// step Desk is on, from the one word list. The song on stage moves for the pleasure of it (letter AD): it sweeps in
// from the last song's wave, then pulses and breathes at its own tempo. Drawing is throttled and stops while the
// window is hidden; under reduced motion nothing moves.

// The run screen's look is RunLook, in Look.swift.

/// What the run screen shows, kept as the run goes: the songs, the totals, the song on stage and those waiting, the
/// quiet line, and the moments.
@MainActor
final class RunWatch: ObservableObject {
    /// The song on stage: when it went on, how long it stays at least, how long its sweep in takes (0: at once), and
    /// the wave of the song before it, which its own grows or shrinks from.
    struct Staged: Equatable { var song: RunSong; var at: Date; var hold: Double; var draw: Double; var from: [Int] }

    @Published private(set) var songs: [RunSong] = []
    @Published private(set) var figures = RunFigures()
    @Published private(set) var staged: Staged?
    @Published private(set) var skipped = 0
    @Published private(set) var saying = ""
    @Published private(set) var sayingIsMoment = false
    /// The moment showing now, by code, until its motion is over.
    @Published private(set) var moment: String?
    @Published private(set) var momentCount = 0
    /// Bumped at most every `RunLook.wallEvery` when songs joined: the wall redraws on it.
    @Published private(set) var wallVersion = 0
    @Published var visible = true { didSet { if visible && !oldValue { wallVersion += 1 } } }
    private(set) var finishedLine: String?
    private(set) var latestBin = -1
    var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    private var queue: [RunSong] = []
    private var fresh: [RunNote] = []
    private var bags: [String: [String]] = [:]
    private var lastSaid = ""
    private var lastWasFact = false
    private var step: RunStage = .reading
    private var musicCD = false
    private var stageTimer: Timer?, sayTimer: Timer?, wallTimer: Timer?
    private var spoken = (done: -1, at: Date.distantPast)

    func start(musicCD: Bool) {
        songs = []; figures = RunFigures(); staged = nil; skipped = 0; fresh = []; queue = []; finishedLine = nil
        self.musicCD = musicCD; step = .reading; lastSaid = ""; saying = ""; moment = nil; latestBin = -1
        spoken = (-1, .distantPast); wallVersion += 1
        nextSaying()
    }

    /// One progress call of the run.
    func take(_ p: RunProgress) {
        if let s = p.song {
            songs.append(s); queue.append(s)
            if let bpm = s.bpm {
                latestBin = max(0, min(p.figures.tempos.count - 1, Int(((bpm - p.figures.tempoLow) / p.figures.tempoStep).rounded(.down))))
            }
            wallSoon()
            if staged == nil || Date() >= staged!.at.addingTimeInterval(staged!.hold) { advance() } else { scheduleStage() }
        }
        figures = p.figures
        for note in p.notes {
            if note.kind == .moment { show(moment: note) } else {
                fresh.removeAll { $0.code == note.code }
                fresh.append(note)
                if fresh.count > 6 { fresh.removeFirst() }
            }
        }
        if p.stage != step { step = p.stage; nextSaying() }
        speak(p)
    }

    func stop() {
        for t in [stageTimer, sayTimer, wallTimer] { t?.invalidate() }
        queue = []
    }

    // MARK: the stage

    private func advance() {
        guard !queue.isEmpty else { return }
        if queue.count > RunLook.queueMax {
            // Falling behind: the oldest waiting go straight to the wall (they are on it already), and the stage says so.
            let drop = queue.count - RunLook.queueMax / 2
            queue.removeFirst(drop); skipped += drop
        }
        let song = queue.removeFirst()
        var hold = max(RunLook.holdMin, RunLook.hold / Double(1 + queue.count))
        // Under reduced motion a song stays at least `holdStill`, so the stage changes as a still picture would.
        if reduceMotion { hold = max(hold, RunLook.holdStill) }
        let ticker = reduceMotion || hold < RunLook.ticker
        staged = Staged(song: song, at: Date(), hold: hold, draw: ticker ? 0 : min(RunLook.draw, hold * RunLook.drawShare), from: staged?.song.wave ?? [])
        if queue.isEmpty && skipped > 0 { stageTimerFire(after: hold) { [weak self] in self?.skipped = 0 } }
        scheduleStage()
    }

    private func scheduleStage() {
        stageTimer?.invalidate()
        guard let s = staged, !queue.isEmpty else { return }
        let wait = max(0, s.at.addingTimeInterval(s.hold).timeIntervalSinceNow)
        stageTimer = once(after: wait) { [weak self] in self?.advance() }
    }

    private func stageTimerFire(after: Double, _ f: @escaping @MainActor () -> Void) { _ = once(after: after, f) }

    private func once(after: Double, _ f: @escaping @MainActor () -> Void) -> Timer {
        Timer.scheduledTimer(withTimeInterval: after, repeats: false) { _ in MainActor.assumeIsolated { f() } }
    }

    private func wallSoon() {
        guard wallTimer == nil else { return }
        wallTimer = once(after: RunLook.wallEvery) { [weak self] in
            guard let self else { return }
            self.wallTimer = nil
            if self.visible { self.wallVersion += 1 } else { self.wallSoon() }
        }
    }

    // MARK: the quiet line and the moments

    private func stepList() -> [String] {
        switch step {
        case .saving: return DeskWords.list("saying.saving")
        case .finishing: return DeskWords.list("saying.finishing")
        case .reading: return (musicCD ? DeskWords.list("saying.disc") : []) + DeskWords.list("saying.reading")
        }
    }

    private func fromBag(_ name: String, _ list: [String]) -> String? {
        // Every line once before any comes round again, and never the same line twice running.
        var bag = bags[name] ?? []
        if bag.isEmpty { bag = list.shuffled() }
        guard !bag.isEmpty else { return nil }
        let i = bag.firstIndex { $0 != lastSaid } ?? 0
        let w = bag.remove(at: i)
        bags[name] = bag
        return w
    }

    private func nextSaying(moment text: String? = nil) {
        var line: String?
        if let text { line = text }
        else if !fresh.isEmpty && !(lastWasFact && Bool.random()) {
            line = Self.words(fresh.removeFirst()); lastWasFact = true
        } else {
            line = fromBag("\(step)\(musicCD ? "-disc" : "")", stepList()); lastWasFact = false
        }
        if let line, line != lastSaid {
            lastSaid = line; saying = line; sayingIsMoment = text != nil
        }
        sayTimer?.invalidate()
        sayTimer = once(after: RunLook.saying) { [weak self] in self?.nextSaying() }
    }

    private func show(moment note: RunNote) {
        let text = Self.words(note)
        if note.code == "finished" { finishedLine = text; return }
        announce(text)
        nextSaying(moment: text)
        guard !reduceMotion else { return }
        moment = note.code; momentCount += 1
        let n = momentCount
        _ = once(after: RunLook.moment) { [weak self] in if self?.momentCount == n { self?.moment = nil } }
    }

    /// A note in its words (`fact.<code>`, `moment.<code>`), its values filled.
    static func words(_ note: RunNote) -> String {
        var v = note.values
        if let m = v["mode"] { v["mode"] = DeskWords.text("mode." + m) }
        if let n = v["n"], let i = Int(n) { v["n"] = i.formatted() }
        if note.code == "finished" { v["duration"] = musicTime(Double(v["seconds"] ?? "0") ?? 0) }
        let key = (note.kind == .moment ? "moment." : "fact.") + note.code
        if let n = note.n { return DeskWords.count(key, n, v.merging(["n": n.formatted()]) { a, _ in a }) }
        return DeskWords.text(key, v)
    }

    static func musicTime(_ s: Double) -> String {
        let h = Int(s) / 3600, m = Int(s) % 3600 / 60
        return h > 0 ? DeskWords.text("figHoursMinutes", ["h": "\(h)", "m": "\(m)"]) : DeskWords.text("figMinutes", ["m": "\(m)"])
    }

    // MARK: screen readers: the plain progress now and then, politely

    private func speak(_ p: RunProgress) {
        guard p.total > 0 else { return }
        let step = max(1, p.total / 10)
        guard p.done - spoken.done >= step || Date().timeIntervalSince(spoken.at) >= 60 || p.done == p.total else { return }
        if p.done == spoken.done { return }
        spoken = (p.done, Date())
        let left = p.remaining.map { Words.timeLeft($0) } ?? ""
        announce(DeskWords.text("announceProgress", ["songs": Words.songsOf(p.done, p.total), "left": left]))
    }

    func announce(_ text: String) {
        guard let w = NSApp.mainWindow ?? NSApp.windows.first else { return }
        NSAccessibility.post(element: w, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }

    // MARK: words for what Desk found

    static func bpm(_ s: RunSong) -> String {
        s.bpm.map { DeskWords.text("bpmValue", ["bpm": String(format: "%.1f", $0)]) } ?? DeskWords.text("none")
    }
    static func key(_ k: RunSong.Key) -> String {
        switch k.kind {
        case .none: return DeskWords.text("keyNotSureValue")
        case .home: return DeskWords.text("homeNoteValue", ["note": k.name ?? ""])
        case .key:
            let key = DeskWords.text("keyValue", ["camelot": k.camelot ?? "", "note": k.name ?? "",
                                                  "mode": DeskWords.text(k.minor == true ? "mode.minor" : "mode.major")])
            return k.uncertain ? Words.keyWithDoubt(key, doubt: DeskWords.text("keyNotSure")) : key
        }
    }
    static func clock(_ s: Double) -> String { RunTally.clock(s) }
    static func whereLine(_ s: RunSong) -> String {
        s.place ?? ((s.folder ?? "").isEmpty ? DeskWords.text("topOfMusicFolder") : s.folder!)
    }
    static func line(_ s: RunSong) -> String {
        let name = s.artist.map { DeskWords.text("wallSongBy", ["number": "\(s.number)", "title": s.title, "artist": $0]) }
            ?? DeskWords.text("wallSong", ["number": "\(s.number)", "title": s.title])
        return Words.wallSong([name, bpm(s), key(s.key), clock(s.seconds), whereLine(s)])
    }
}

// MARK: the views

struct RunCard<Content: View>: View {
    var moment = false
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(RunLook.cardPadding).frame(maxWidth: .infinity, alignment: .leading)
            .background(RunLook.card, in: RoundedRectangle(cornerRadius: RunLook.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: RunLook.cardRadius).stroke(RunLook.accent.opacity(moment ? RunLook.momentRingOpacity : 0), lineWidth: RunLook.momentRingWidth))
            .animation(.easeOut(duration: RunLook.momentFlash), value: moment)
    }
}

/// The song on stage: its own wave drawing in with its bars marked, and what Desk found in it.
struct StageView: View {
    @ObservedObject var watch: RunWatch
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        RunCard(moment: watch.moment == "first") {
            if let s = watch.staged {
                HStack(alignment: .center, spacing: RunLook.stageGap) {
                    // Moving the whole time it is on stage (letter AD), at most `frame` apart; still under reduced
                    // motion and while the window is hidden.
                    TimelineView(.animation(minimumInterval: RunLook.frame, paused: reduce || !watch.visible)) { tl in
                        Canvas { gc, size in
                            let t0 = CACurrentMediaTime()
                            StageView.draw(s, elapsed: tl.date.timeIntervalSince(s.at), still: reduce, in: &gc, size: size)
                            RunCost.add(from: t0)
                        }
                    }
                    .frame(height: RunLook.stageHeight).frame(maxWidth: .infinity)
                    .accessibilityLabel(DeskWords.text("stageWaveLabel", ["title": s.song.title]))
                    facts(s.song).frame(maxWidth: .infinity, alignment: .leading)
                        .id(s.song.id)
                        .transition(.opacity)
                }
                .animation(reduce || s.draw == 0 ? nil : .easeInOut(duration: RunLook.fade), value: s.song.id)
            } else {
                Text(DeskWords.text("stageFirstSoon")).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: RunLook.stageHeight)
            }
        }
    }

    private func facts(_ s: RunSong) -> some View {
        VStack(alignment: .leading, spacing: RunLook.stageFactsGap) {
            HStack(spacing: RunLook.stageNameGap) {
                Text(s.title).font(RunLook.stageFont).lineLimit(1)
                if let a = s.artist { Text(a).foregroundStyle(.secondary).lineLimit(1) }
                if s.before {
                    Text(DeskWords.text("stageBefore")).font(RunLook.chipFont).foregroundStyle(.secondary)
                        .padding(.horizontal, RunLook.chipPaddingH).padding(.vertical, RunLook.chipPaddingV).background(.quaternary, in: Capsule())
                }
            }
            HStack(alignment: .top, spacing: RunLook.stageFactsRowGap) {
                fact("stageTempo", RunWatch.bpm(s), color: RunLook.amber)
                fact("stageKey", RunWatch.key(s.key), color: s.key.kind == .key ? .primary : .secondary)
                fact("stageBars", s.bars.map(String.init) ?? DeskWords.text("none"))
                fact("stageLength", RunWatch.clock(s.seconds))
            }
            fact("stageWhere", RunWatch.whereLine(s))
            if watch.skipped > 0 { Text(DeskWords.count("stageMore", watch.skipped)).font(RunLook.stageNoteFont).foregroundStyle(.tertiary) }
            else if s.wave.isEmpty { Text(DeskWords.text("stageNoWave")).font(RunLook.stageNoteFont).foregroundStyle(.tertiary) }
        }
    }

    private func fact(_ label: String, _ value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: RunLook.stageFactGap) {
            Text(DeskWords.text(label)).font(RunLook.labelFont).foregroundStyle(.tertiary)
            Text(value).fontWeight(RunLook.stageValueWeight).monospacedDigit().foregroundStyle(color).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    static func draw(_ st: RunWatch.Staged, elapsed: Double, still: Bool, in gc: inout GraphicsContext, size: CGSize) {
        let s = st.song, w = size.width, markH = (size.height * RunLook.stageMarkShare).rounded(), h = size.height - markH, mid = h / 2
        guard w > 0, h > 0 else { return }
        let m = StageMotion(bpm: s.bpm, elapsed: elapsed, sweep: st.draw, still: still)
        let edge = CGFloat(m.front) * w
        gc.fill(Path(CGRect(x: 0, y: mid.rounded(), width: w, height: RunLook.stageLine)), with: .color(Color(nsColor: RunLook.waveNone)))
        let n = RunSong.waveLength, slot = w / CGFloat(n)
        // The wave: mirrored, through the middle of each stretch; each stretch moving from the last song's height to
        // this one's, then breathing with the song (StageMotion).
        let playX = m.playhead.map { CGFloat($0) * w }
        let halves: [CGFloat] = (0..<n).map { i in
            let base = m.height(i, of: n, from: st.from, to: s.wave)
            let x = (CGFloat(i) + 0.5) * slot
            let lift = playX.map { m.lift(distance: Double(abs(x - $0) / w)) } ?? 0
            return CGFloat(base * m.scale(lift: lift)) * h * RunLook.stageWaveRoom
        }
        if halves.contains(where: { $0 > 0 }) {
            func half(_ i: Int) -> CGFloat { max(RunLook.stageWaveMin, halves[max(0, min(n - 1, i))]) }
            var path = Path()
            path.move(to: CGPoint(x: 0, y: mid - half(0)))
            for i in 0..<n { path.addLine(to: CGPoint(x: (CGFloat(i) + 0.5) * slot, y: mid - half(i))) }
            path.addLine(to: CGPoint(x: w, y: mid - half(n - 1)))
            path.addLine(to: CGPoint(x: w, y: mid + half(n - 1)))
            for i in stride(from: n - 1, through: 0, by: -1) { path.addLine(to: CGPoint(x: (CGFloat(i) + 0.5) * slot, y: mid + half(i))) }
            path.addLine(to: CGPoint(x: 0, y: mid + half(0)))
            path.closeSubpath()
            gc.fill(path, with: .color(Color(nsColor: RunLook.wave)))
            // The playhead: a soft band of light crossing the wave.
            if let x = playX {
                let band = CGFloat(RunLook.playheadWidth) * w
                gc.fill(path, with: .linearGradient(Gradient(colors: [RunLook.playheadGlow.opacity(0), RunLook.playheadGlow, RunLook.playheadGlow.opacity(0)]),
                                                    startPoint: CGPoint(x: x - band, y: 0), endPoint: CGPoint(x: x + band, y: 0)))
            }
        }
        // Its bars marked as the sweep passes: a cut through the wave every 8 bars and a mark below it, a longer one
        // every 32.
        if let bars = s.bars, bars > 0 {
            var b = 8
            while b < bars {
                let x = (CGFloat(b) / CGFloat(bars) * w).rounded()
                if x > edge { break }
                let strong = b % 32 == 0
                gc.blendMode = .clear
                gc.fill(Path(CGRect(x: x, y: 0, width: strong ? RunLook.stageTickStrongWidth : RunLook.stageTickWidth, height: h)), with: .color(.black))
                gc.blendMode = .normal
                gc.fill(Path(CGRect(x: x, y: h + RunLook.stageTickGap, width: RunLook.stageTickWidth, height: max(0, strong ? markH - RunLook.stageTickGap : (markH - RunLook.stageTickGap) * RunLook.stageTickShort))),
                        with: .color(strong ? RunLook.tickStrong : RunLook.tick))
                b += 8
            }
        }
    }
}

/// How the song on stage moves at one moment (letter AD), the same arithmetic as the pages' run.js: the sweep from
/// the last song's wave to this one's, a pulse on each beat of its tempo, a slow breath over a few bars, and a playhead
/// crossing it. Every time is held to nothing or more (a frame's clock can read a moment before the song went on
/// stage) and every index to the wave it reads, however short.
struct StageMotion {
    /// The share of the width the sweep has reached, 0 to 1.
    let front: Double
    /// Where the playhead is, 0 to 1 across, once the sweep is over; nil before then and when still.
    let playhead: Double?
    let elapsed: Double, sweep: Double, still: Bool
    /// The swell now from the pulse and the breath, as a share of the height.
    let swell: Double

    init(bpm: Double?, elapsed: Double, sweep: Double, still: Bool) {
        let e = elapsed.isFinite ? max(0, elapsed) : 0
        let sw = sweep.isFinite ? max(0, sweep) : 0
        self.elapsed = e; self.sweep = sw; self.still = still
        let beat = Self.beat(bpm)
        front = still || sw <= 0 ? 1 : max(0, min(1, e / max(sw * RunLook.sweepStagger, .ulpOfOne)))
        guard !still else { swell = 0; playhead = nil; return }
        if let beat {
            let ph = e / beat, k = ph.rounded(.down), frac = ph - k
            let down = k.truncatingRemainder(dividingBy: RunLook.beatsInBar) == 0
            let pulse = (down ? RunLook.pulseDownbeat : RunLook.pulse) * exp(-RunLook.pulseFall * frac)
            swell = pulse + RunLook.breath * 0.5 * (1 - cos(2 * .pi * ph / (RunLook.beatsInBar * RunLook.breathBars)))
        } else {
            swell = RunLook.breath * 0.5 * (1 - cos(2 * .pi * e / RunLook.breathNoTempoSeconds))
        }
        let cross = beat.map { $0 * RunLook.beatsInBar * RunLook.playheadBars } ?? RunLook.playheadNoTempoSeconds
        if e >= sw, cross > 0 {
            let t = (e - sw) / cross
            playhead = t - t.rounded(.down)
        } else { playhead = nil }
    }

    /// Seconds between pulses: the song's beat, doubled or halved into `beatFastest` to `beatSlowest`; nil with no tempo.
    static func beat(_ bpm: Double?) -> Double? {
        guard let bpm, bpm.isFinite, bpm > 0 else { return nil }
        var b = 60 / bpm, turns = 0
        while b < RunLook.beatFastest && turns < 16 { b *= 2; turns += 1 }
        while b > RunLook.beatSlowest && turns < 32 { b /= 2; turns += 1 }
        return b
    }

    /// A wave's height at stretch `i` of `n`, 0 to 1 on the one curve every song shares; 0 with no wave.
    static func shape(_ wave: [Int], _ i: Int, of n: Int) -> Double {
        guard !wave.isEmpty, n > 0 else { return 0 }
        let j = max(0, min(wave.count - 1, i * wave.count / n))
        return pow(Double(max(0, min(99, wave[j]))) / 99, RunLook.waveCurve)
    }

    /// Stretch `i`'s height now, on its way from the last song's wave to this one's: each stretch starts in turn from
    /// the left and settles with a small overshoot.
    func height(_ i: Int, of n: Int, from old: [Int], to new: [Int]) -> Double {
        let target = Self.shape(new, i, of: n)
        guard !still, sweep > 0 else { return target }
        let start = Double(i) / Double(max(1, n - 1)) * sweep * RunLook.sweepStagger
        let span = max(sweep * (1 - RunLook.sweepStagger), .ulpOfOne)
        let x = max(0, min(1, (elapsed - start) / span)), c = RunLook.morphOvershoot
        let eased = 1 + (c + 1) * pow(x - 1, 3) + c * pow(x - 1, 2)
        let was = Self.shape(old, i, of: n)
        return max(0, was + (target - was) * eased)
    }

    /// The playhead's lift at a distance from it (a share of the width).
    func lift(distance: Double) -> Double {
        let d = distance / RunLook.playheadWidth
        return d.isFinite && d < 1 ? RunLook.playheadLift * (1 - d) : 0
    }

    /// The share of the room a height takes now: at the fullest swell the wave fills `stageWaveRoom`.
    func scale(lift: Double) -> Double {
        (1 + swell + lift) / (1 + RunLook.pulseDownbeat + RunLook.breath + RunLook.playheadLift)
    }
}

/// What Desk has found so far, each a true count.
struct FiguresView: View {
    @ObservedObject var watch: RunWatch
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let f = watch.figures
        HStack(alignment: .top, spacing: RunLook.figuresGap) {
            RunCard(moment: watch.moment == "hour") {
                VStack(alignment: .leading, spacing: RunLook.figureGap) {
                    label("figMusic")
                    Text(RunWatch.musicTime(f.seconds)).font(RunLook.bigFont)
                }
            }.frame(maxWidth: RunLook.musicFigureWidth)
            RunCard {
                VStack(alignment: .leading, spacing: RunLook.figureGap) {
                    label("figTempos")
                    Canvas { gc, size in FiguresView.histogram(f, latest: watch.latestBin, in: &gc, size: size) }
                        .frame(height: RunLook.figureHeight)
                    Text(temposText(f)).font(RunLook.figureTextFont).foregroundStyle(.secondary).lineLimit(2)
                }
                .accessibilityElement(children: .ignore).accessibilityLabel(Words.figureLabel(DeskWords.text("figTempos"), temposText(f)))
            }
            RunCard {
                VStack(alignment: .leading, spacing: RunLook.figureGap) {
                    label("figKeys")
                    Canvas { gc, size in FiguresView.wheel(f, in: &gc, size: size) }
                        .frame(width: RunLook.figureHeight, height: RunLook.figureHeight).frame(maxWidth: .infinity)
                        .rotationEffect(.degrees(watch.moment == "wheel" && !reduce ? RunLook.wheelTurn : 0))
                        .animation(watch.moment == "wheel" && !reduce ? .easeInOut(duration: RunLook.moment) : nil, value: watch.moment)
                    Text(keysText(f)).font(RunLook.figureTextFont).foregroundStyle(.secondary).lineLimit(2)
                }
                .accessibilityElement(children: .ignore).accessibilityLabel(Words.figureLabel(DeskWords.text("figKeys"), keysText(f)))
            }
            RunCard {
                VStack(alignment: .leading, spacing: RunLook.figureListGap) {
                    row("figNeedName", f.needName.formatted())
                    row("figSameFile", f.sameFile.formatted())
                    row("figCopies", f.copies.map { $0.formatted() } ?? DeskWords.text("figCopiesLater"))
                    row("figNotIn", f.notIn.formatted())
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func label(_ k: String) -> some View { Text(DeskWords.text(k)).font(RunLook.figureLabelFont).foregroundStyle(.tertiary) }
    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(DeskWords.text(k)).foregroundStyle(.secondary); Spacer(); Text(v).fontWeight(RunLook.figureValueWeight).monospacedDigit() }.font(RunLook.figureListFont)
            .accessibilityElement(children: .combine)
    }

    private func temposText(_ f: RunFigures) -> String {
        let with = f.songs - f.noTempo
        guard with > 0, let lo = f.slowest, let hi = f.fastest else { return DeskWords.text("figTemposNone") }
        let top = f.tempos.indices.max { f.tempos[$0] < f.tempos[$1] || (f.tempos[$0] == f.tempos[$1] && $0 > $1) } ?? 0
        return DeskWords.text("figTemposText", ["songs": Words.songs(with), "low": "\(Int(lo.rounded()))", "high": "\(Int(hi.rounded()))",
                                                "mode": "\(Int((f.tempoLow + Double(top) * f.tempoStep + f.tempoStep / 2).rounded()))"])
    }

    private func keysText(_ f: RunFigures) -> String {
        var parts = [DeskWords.text("figKeysText", ["n": "\(f.keysFound)"])]
        let homes = f.home.reduce(0, +)
        if homes > 0 { parts.append(DeskWords.count("figHomeOnly", homes)) }
        if f.noKey > 0 { parts.append(DeskWords.count("figNoKey", f.noKey)) }
        return Words.keysFigure(parts)
    }

    static func histogram(_ f: RunFigures, latest: Int, in gc: inout GraphicsContext, size: CGSize) {
        let most = max(1, f.tempos.max() ?? 1), slot = size.width / CGFloat(f.tempos.count), barW = max(RunLook.histBarMinWidth, slot - RunLook.histBarGap)
        gc.fill(Path(CGRect(x: 0, y: size.height - RunLook.histBaseline, width: size.width, height: RunLook.histBaseline)), with: .color(Color(nsColor: RunLook.waveNone)))
        for (i, c) in f.tempos.enumerated() where c > 0 {
            let bh = max(RunLook.histBarMin, CGFloat(c) / CGFloat(most) * (size.height - RunLook.histTop))
            gc.fill(Path(CGRect(x: CGFloat(i) * slot, y: size.height - bh, width: barW, height: bh)),
                    with: .color(Color(nsColor: i == latest ? RunLook.waveNew : RunLook.wave)))
        }
    }

    /// The wheel of the twelve home notes round the circle of fifths: the outer ring major, the inner minor, a dot inside
    /// for a song whose home note alone Desk found.
    static let fifths = [0, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10, 5]
    static func wheel(_ f: RunFigures, in gc: inout GraphicsContext, size: CGSize) {
        let s = min(size.width, size.height) / RunLook.wheelBox, c = CGPoint(x: size.width / 2, y: size.height / 2)
        let most = max(1, max(f.major.max() ?? 0, f.minor.max() ?? 0))
        for (i, pc) in fifths.enumerated() {
            let a0 = Angle.degrees(Double(i) * 30 - 105 + RunLook.wheelCellGap), a1 = Angle.degrees(Double(i) * 30 - 75 - RunLook.wheelCellGap)
            for (counts, r0, r1) in [(f.major, RunLook.wheelMajorIn, RunLook.wheelMajorOut), (f.minor, RunLook.wheelMinorIn, RunLook.wheelMinorOut)] {
                var p = Path()
                p.addArc(center: c, radius: r1 * s, startAngle: a0, endAngle: a1, clockwise: false)
                p.addArc(center: c, radius: r0 * s, startAngle: a1, endAngle: a0, clockwise: true)
                p.closeSubpath()
                let n = counts[pc]
                gc.fill(p, with: .color(n > 0 ? RunLook.accent.opacity(RunLook.wheelFillMin + RunLook.wheelFillRange * Double(n) / Double(most)) : RunLook.wheelEmpty))
            }
            if f.home[pc] > 0 {
                let am = (Double(i) * 30 - 90) * .pi / 180, r = min(RunLook.wheelDotMax, RunLook.wheelDotBase + Double(f.home[pc]).squareRoot()) * s
                let at = CGPoint(x: c.x + RunLook.wheelHomeR * s * cos(am), y: c.y + RunLook.wheelHomeR * s * sin(am))
                gc.fill(Path(ellipseIn: CGRect(x: at.x - r, y: at.y - r, width: r * 2, height: r * 2)), with: .color(RunLook.wheelHome))
            }
        }
    }
}

/// The crate filling up: one line a song, as they joined, top to bottom then the next column. Hovering or choosing a
/// line names the song; the arrow keys move along them.
struct WallView: View {
    @ObservedObject var watch: RunWatch
    var title: String
    @State private var pick: Int?
    @State private var size: CGSize = .zero
    @FocusState private var focused: Bool
    @Environment(\.displayScale) private var scale

    var body: some View {
        RunCard(moment: watch.moment == "disc") {
            VStack(alignment: .leading, spacing: RunLook.wallCardGap) {
                HStack(alignment: .firstTextBaseline, spacing: RunLook.wallHeadGap) {
                    Text(title).font(RunLook.wallTitleFont)
                    Text(pick.flatMap { watch.songs.indices.contains($0) ? RunWatch.line(watch.songs[$0]) : nil } ?? "")
                        .font(RunLook.wallNameFont).foregroundStyle(.secondary).lineLimit(1)
                }
                GeometryReader { geo in
                    let picture = WallPicture.make(watch.songs, version: watch.wallVersion, size: geo.size, scale: scale, pick: pick)
                    Image(decorative: picture.image ?? WallPicture.empty, scale: scale)
                        .resizable().interpolation(.none)
                        .onContinuousHover { phase in
                            switch phase {
                            case let .active(p): pick = picture.index(at: p)
                            case .ended: if !focused { pick = nil }
                            }
                        }
                        .onChange(of: geo.size, initial: true) { _, s in size = s }
                }
                .frame(height: RunLook.wallHeight)
                .focusable().focused($focused)
                .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .home, .end]) { press in
                    move(press.key); return .handled
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(watch.songs.isEmpty ? DeskWords.text("wallEmpty") : Words.wallLabel(title, songs: watch.songs.count))
                .accessibilityValue(pick.flatMap { watch.songs.indices.contains($0) ? RunWatch.line(watch.songs[$0]) : nil } ?? "")
                Text(DeskWords.text("wallHelp")).font(RunLook.wallHelpFont).foregroundStyle(.tertiary)
            }
        }
    }

    private func move(_ key: KeyEquivalent) {
        let n = watch.songs.count
        guard n > 0 else { return }
        let rows = WallPicture.rows(n, size: size, scale: scale)
        var i = pick ?? (key == .end ? n - 1 : 0)
        if pick != nil {
            switch key {
            case .downArrow: i += 1
            case .upArrow: i -= 1
            case .rightArrow: i += rows
            case .leftArrow: i -= rows
            case .home: i = 0
            case .end: i = n - 1
            default: break
            }
        }
        pick = max(0, min(n - 1, i))
        if let p = pick { watch.announce(RunWatch.line(watch.songs[p])) }
    }
}

/// The wall as a picture, drawn pixel by pixel as the pages draw it (one song a line: a wave where a line is tall
/// enough, else a line of brightness), kept until the songs, the size or the song picked change.
@MainActor
enum WallPicture {
    struct Plan { var wave: Bool; var cols: Int; var rows: Int; var lh: CGFloat; var gap: CGFloat; var cw: CGFloat; var scale: CGFloat
        func index(at p: CGPoint, count: Int) -> Int? {
            let x = p.x * scale, y = p.y * scale
            let col = Int(x / (cw + gap)), row = Int(y / lh)
            let i = col * rows + row
            return col >= 0 && col < cols && row >= 0 && row < rows && i < count ? i : nil
        }
    }
    struct Made { var image: CGImage?; var plan: Plan?; var count: Int
        func index(at p: CGPoint) -> Int? { plan?.index(at: p, count: count) }
    }
    private static var cache: (key: String, made: Made)?
    static let empty: CGImage = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!

    static func plan(_ count: Int, w: CGFloat, h: CGFloat, scale: CGFloat) -> Plan {
        let gap = (RunLook.wallGap * scale).rounded(), maxCols = max(1, Int((w + gap) / (RunLook.wallColMin * scale + gap)))
        for cols in 1...maxCols {
            let rows = Int((Double(count) / Double(cols)).rounded(.up))
            if h / CGFloat(rows) >= RunLook.wallWaveMin * scale {
                return Plan(wave: true, cols: cols, rows: rows, lh: h / CGFloat(rows), gap: gap, cw: (w - gap * CGFloat(cols - 1)) / CGFloat(cols), scale: scale)
            }
        }
        let dgap = max(1, (RunLook.wallDenseGap * scale).rounded())
        let maxDense = max(1, Int((w + dgap) / (RunLook.wallDenseColMin * scale + dgap)))
        let line = max(1, RunLook.wallDenseLine * scale)
        var cols = min(maxDense, max(1, Int((Double(count) / Double(max(1, (h / line).rounded(.down)))).rounded(.up))))
        // More songs than pixel rows even at the narrowest columns: narrower columns, one pixel a song.
        cols = max(cols, Int((Double(count) / Double(h)).rounded(.up)))
        let rows = Int((Double(count) / Double(cols)).rounded(.up))
        return Plan(wave: false, cols: cols, rows: rows, lh: max(1, h / CGFloat(rows)), gap: dgap, cw: (w - dgap * CGFloat(cols - 1)) / CGFloat(cols), scale: scale)
    }

    static func rows(_ count: Int, size: CGSize, scale: CGFloat) -> Int {
        plan(count, w: size.width * scale, h: size.height * scale, scale: scale).rows
    }

    static func make(_ songs: [RunSong], version: Int, size: CGSize, scale: CGFloat, pick: Int?) -> Made {
        let key = "\(version) \(songs.count) \(Int(size.width))x\(Int(size.height)) \(scale) \(pick ?? -1)"
        if let c = cache, c.key == key { return c.made }
        let made = draw(songs, size: size, scale: scale, pick: pick)
        cache = (key, made)
        return made
    }

    private static func rgba(_ c: NSColor) -> (UInt8, UInt8, UInt8, Double) {
        let s = c.usingColorSpace(.deviceRGB) ?? c
        func part(_ v: CGFloat) -> UInt8 { UInt8(max(0, min(255, (v.isFinite ? v : 0) * 255))) }
        return (part(s.redComponent), part(s.greenComponent), part(s.blueComponent), Double(max(0, min(1, s.alphaComponent))))
    }

    private static func draw(_ songs: [RunSong], size: CGSize, scale: CGFloat, pick: Int?) -> Made {
        let w = max(1, Int(size.width * scale)), h = max(1, Int(size.height * scale))
        guard !songs.isEmpty, size.width > 0 else { return Made(image: nil, plan: nil, count: 0) }
        let L = plan(songs.count, w: CGFloat(w), h: CGFloat(h), scale: scale)
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let cWave = rgba(RunLook.wave), cQuiet = rgba(RunLook.waveQuiet), cNew = rgba(RunLook.waveNew),
            cPick = rgba(RunLook.wavePick), cNone = rgba(RunLook.waveNone)
        func put(_ x: Int, _ y: Int, _ c: (UInt8, UInt8, UInt8, Double), _ a: Double) {
            guard x >= 0, x < w, y >= 0, y < h else { return }
            let o = (y * w + x) * 4, al = max(0, min(1, c.3 * a))
            px[o] = UInt8(Double(c.0) * al); px[o + 1] = UInt8(Double(c.1) * al); px[o + 2] = UInt8(Double(c.2) * al); px[o + 3] = UInt8(255 * al)
        }
        let n = RunSong.waveLength, last = songs.count - 1
        for (i, s) in songs.enumerated() {
            let col = i / L.rows, row = i % L.rows
            let x0 = Int((CGFloat(col) * (L.cw + L.gap)).rounded()), x1 = min(w, Int((CGFloat(col) * (L.cw + L.gap) + L.cw).rounded()))
            let y0 = Int(CGFloat(row) * L.lh), y1 = min(h, max(y0 + 1, Int(CGFloat(row + 1) * L.lh)))
            guard y0 < h, x1 > x0 else { continue }
            let c = i == pick ? cPick : i == last ? cNew : cWave
            let cw = Double(x1 - x0)
            if s.wave.isEmpty { let y = (y0 + y1) / 2; for x in x0..<x1 { put(x, y, cNone, 1) }; continue }
            for x in x0..<x1 {
                let v = pow(Double(s.wave[max(0, min(n - 1, s.wave.count - 1, Int(Double(x - x0) / cw * Double(n))))]) / 99, RunLook.waveCurve)
                if L.wave {
                    let mid = Double(y0 + y1 - 1) / 2, half = max(RunLook.wallWaveMinHalf, v * Double(y1 - y0) * RunLook.wallWaveRoom)
                    var y = max(y0, Int((mid - half).rounded()))
                    while y <= min(y1 - 1, Int((mid + half).rounded())) { put(x, y, c, 1); y += 1 }
                } else {
                    let cc = (c == cWave) ? (v < RunLook.wallDenseQuiet ? cQuiet : cWave) : c
                    for y in y0..<y1 { put(x, y, cc, RunLook.wallDenseDim + RunLook.wallDenseBright * v) }
                }
            }
        }
        let data = Data(px) as CFData
        let image = CGDataProvider(data: data).flatMap {
            CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: $0, decode: nil,
                    shouldInterpolate: false, intent: .defaultIntent)
        }
        return Made(image: image, plan: L, count: songs.count)
    }
}
