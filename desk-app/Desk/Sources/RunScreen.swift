import SwiftUI
import AppKit
import DeckieDesk

// The run screen on the Mac (D37): the same screen as the Windows and Linux window's (desk-web/run.js), from the same
// data, which the Mac gets from DeskRun directly (RunProgress's song, notes and figures). Everything drawn is a song
// Desk read; every number is counted by the core; every sentence is one the core said is true, or a line about the
// step Desk is on, from the one word list. Drawing is throttled and stops while the window is hidden; under reduced
// motion nothing moves.

/// The run screen's look: every colour, size and time it uses, named, for the design pass to change in one place
/// (desk-web/desk.css's run-screen variables are the same values).
enum RunLook {
    static let accent = Color(red: 0.706, green: 0.565, blue: 1.0)          // #b490ff: the site's and the booth's lavender
    static let amber = Color(red: 1.0, green: 0.753, blue: 0.251)           // #ffc040: a tempo reading, as the booth's pitch line
    static let wave = NSColor(red: 0.706, green: 0.565, blue: 1.0, alpha: 0.82)
    static let waveQuiet = NSColor(red: 0.706, green: 0.565, blue: 1.0, alpha: 0.28)
    static let waveNew = NSColor(red: 0.925, green: 0.894, blue: 1.0, alpha: 1)
    static let wavePick = NSColor(red: 1.0, green: 0.753, blue: 0.251, alpha: 1)
    static let waveNone = NSColor(white: 0.5, alpha: 0.25)
    static let tick = Color.primary.opacity(0.22), tickStrong = Color.primary.opacity(0.45)
    static let wheelEmpty = Color.primary.opacity(0.07)
    static let wheelHome = Color.secondary
    static let card = Color.primary.opacity(0.045)
    static let cardRadius: CGFloat = 16
    static let gap: CGFloat = 14
    static let cardPadding: CGFloat = 14
    static let stageHeight: CGFloat = 120
    static let figureHeight: CGFloat = 70
    static let wallHeight: CGFloat = 200
    /// Points a wall line needs to be drawn as a wave, the narrowest column of waves, of brightness lines.
    static let wallWaveMin: CGFloat = 6, wallColMin: CGFloat = 150, wallDenseColMin: CGFloat = 18
    /// Points a brightness line aims for, before the columns run out (then lines thin to a pixel).
    static let wallDenseLine: CGFloat = 3
    /// How loudness becomes height, the same for every song (the pages' --wave-curve).
    static let waveCurve = 2.2
    static let bigFont = Font.system(size: 26, weight: .bold).monospacedDigit()
    static let stageFont = Font.system(size: 17, weight: .semibold)
    static let labelFont = Font.caption2
    /// Seconds: a wave drawing in; a song on stage with nothing waiting, and with many; a fade; each quiet line; a
    /// moment; the wall's quickest redraw.
    static let draw = 0.9, hold = 3.2, holdMin = 0.3, holdStill = 2.0, fade = 0.42, saying = 7.0, moment = 1.6, wallEvery = 0.25
    /// Songs waiting for the stage before the oldest go straight to the wall.
    static let queueMax = 24
    static let frame = 1.0 / 30
}

/// What the run screen shows, kept as the run goes: the songs, the totals, the song on stage and those waiting, the
/// quiet line, and the moments.
@MainActor
final class RunWatch: ObservableObject {
    struct Staged: Equatable { var song: RunSong; var at: Date; var hold: Double; var draw: Double }

    @Published private(set) var songs: [RunSong] = []
    @Published private(set) var figures = RunFigures()
    @Published private(set) var staged: Staged?
    @Published private(set) var drawing = false
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
    private var stageTimer: Timer?, sayTimer: Timer?, wallTimer: Timer?, drawTimer: Timer?
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
        for t in [stageTimer, sayTimer, wallTimer, drawTimer] { t?.invalidate() }
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
        let ticker = reduceMotion || hold < 0.9
        staged = Staged(song: song, at: Date(), hold: hold, draw: ticker ? 0 : min(RunLook.draw, hold * 0.45))
        if queue.isEmpty && skipped > 0 { stageTimerFire(after: hold) { [weak self] in self?.skipped = 0 } }
        drawing = staged!.draw > 0 && visible
        drawTimer?.invalidate()
        if drawing { drawTimer = once(after: staged!.draw) { [weak self] in self?.drawing = false } }
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
            return DeskWords.text("keyValue", ["camelot": k.camelot ?? "", "note": k.name ?? "",
                                               "mode": DeskWords.text(k.minor == true ? "mode.minor" : "mode.major")])
                + (k.uncertain ? DeskWords.text("keyNotSure") : "")
        }
    }
    static func clock(_ s: Double) -> String { RunTally.clock(s) }
    static func whereLine(_ s: RunSong) -> String {
        s.place ?? ((s.folder ?? "").isEmpty ? DeskWords.text("topOfMusicFolder") : s.folder!)
    }
    static func line(_ s: RunSong) -> String {
        let name = s.artist.map { DeskWords.text("wallSongBy", ["number": "\(s.number)", "title": s.title, "artist": $0]) }
            ?? DeskWords.text("wallSong", ["number": "\(s.number)", "title": s.title])
        return [name, bpm(s), key(s.key), clock(s.seconds), whereLine(s)].joined(separator: "  ·  ")
    }
}

// MARK: the views

struct RunCard<Content: View>: View {
    var moment = false
    @ViewBuilder var content: Content
    var body: some View {
        content.padding(RunLook.cardPadding).frame(maxWidth: .infinity, alignment: .leading)
            .background(RunLook.card, in: RoundedRectangle(cornerRadius: RunLook.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: RunLook.cardRadius).stroke(RunLook.accent.opacity(moment ? 0.6 : 0), lineWidth: 2))
            .animation(.easeOut(duration: RunLook.moment / 2), value: moment)
    }
}

/// The song on stage: its own wave drawing in with its bars marked, and what Desk found in it.
struct StageView: View {
    @ObservedObject var watch: RunWatch
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        RunCard(moment: watch.moment == "first") {
            if let s = watch.staged {
                HStack(alignment: .center, spacing: 20) {
                    TimelineView(.animation(minimumInterval: RunLook.frame, paused: reduce || !watch.drawing || !watch.visible)) { tl in
                        Canvas { gc, size in
                            let p = s.draw > 0 ? min(1, tl.date.timeIntervalSince(s.at) / s.draw) : 1
                            StageView.draw(s.song, progress: reduce ? 1 : p, in: &gc, size: size)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(s.title).font(RunLook.stageFont).lineLimit(1)
                if let a = s.artist { Text(a).foregroundStyle(.secondary).lineLimit(1) }
                if s.before {
                    Text(DeskWords.text("stageBefore")).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 1).background(.quaternary, in: Capsule())
                }
            }
            HStack(alignment: .top, spacing: 22) {
                fact("stageTempo", RunWatch.bpm(s), color: RunLook.amber)
                fact("stageKey", RunWatch.key(s.key), color: s.key.kind == .key ? .primary : .secondary)
                fact("stageBars", s.bars.map(String.init) ?? DeskWords.text("none"))
                fact("stageLength", RunWatch.clock(s.seconds))
            }
            fact("stageWhere", RunWatch.whereLine(s))
            if watch.skipped > 0 { Text(DeskWords.count("stageMore", watch.skipped)).font(.caption).foregroundStyle(.tertiary) }
            else if s.wave.isEmpty { Text(DeskWords.text("stageNoWave")).font(.caption).foregroundStyle(.tertiary) }
        }
    }

    private func fact(_ label: String, _ value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(DeskWords.text(label)).font(RunLook.labelFont).foregroundStyle(.tertiary)
            Text(value).fontWeight(.semibold).monospacedDigit().foregroundStyle(color).lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    static func draw(_ s: RunSong, progress p: Double, in gc: inout GraphicsContext, size: CGSize) {
        let w = size.width, markH = (size.height * 0.12).rounded(), h = size.height - markH, mid = h / 2, edge = p * w
        gc.fill(Path(CGRect(x: 0, y: mid.rounded(), width: edge, height: 1)), with: .color(Color(nsColor: RunLook.waveNone)))
        let n = RunSong.waveLength, slot = w / CGFloat(n)
        if !s.wave.isEmpty {
            // The wave: mirrored, through the middle of each stretch, drawn in from the left as far as `p`.
            let shown = min(n, Int((p * Double(n)).rounded(.up)))
            func half(_ i: Int) -> CGFloat { max(1, CGFloat(pow(Double(s.wave[i]) / 99, RunLook.waveCurve)) * h * 0.48) }
            var path = Path()
            path.move(to: CGPoint(x: 0, y: mid - half(0)))
            for i in 0..<shown { path.addLine(to: CGPoint(x: min(edge, (CGFloat(i) + 0.5) * slot), y: mid - half(i))) }
            path.addLine(to: CGPoint(x: edge, y: mid - half(max(0, shown - 1))))
            path.addLine(to: CGPoint(x: edge, y: mid + half(max(0, shown - 1))))
            for i in stride(from: shown - 1, through: 0, by: -1) { path.addLine(to: CGPoint(x: min(edge, (CGFloat(i) + 0.5) * slot), y: mid + half(i))) }
            path.addLine(to: CGPoint(x: 0, y: mid + half(0)))
            path.closeSubpath()
            gc.fill(path, with: .color(Color(nsColor: RunLook.wave)))
        }
        // Its bars marked: a cut through the wave every 8 bars and a mark below it, a longer one every 32.
        if let bars = s.bars, bars > 0 {
            var b = 8
            while b < bars {
                let x = (CGFloat(b) / CGFloat(bars) * w).rounded()
                if x > edge { break }
                let strong = b % 32 == 0
                gc.blendMode = .clear
                gc.fill(Path(CGRect(x: x, y: 0, width: strong ? 2 : 1, height: h)), with: .color(.black))
                gc.blendMode = .normal
                gc.fill(Path(CGRect(x: x, y: h + 2, width: 1, height: strong ? markH - 2 : (markH - 2) / 2)),
                        with: .color(strong ? RunLook.tickStrong : RunLook.tick))
                b += 8
            }
        }
    }
}

/// What Desk has found so far, each a true count.
struct FiguresView: View {
    @ObservedObject var watch: RunWatch
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        let f = watch.figures
        HStack(alignment: .top, spacing: 10) {
            RunCard(moment: watch.moment == "hour") {
                VStack(alignment: .leading, spacing: 6) {
                    label("figMusic")
                    Text(RunWatch.musicTime(f.seconds)).font(RunLook.bigFont)
                }
            }.frame(maxWidth: 180)
            RunCard {
                VStack(alignment: .leading, spacing: 6) {
                    label("figTempos")
                    Canvas { gc, size in FiguresView.histogram(f, latest: watch.latestBin, in: &gc, size: size) }
                        .frame(height: RunLook.figureHeight)
                    Text(temposText(f)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                .accessibilityElement(children: .ignore).accessibilityLabel(DeskWords.text("figTempos") + ": " + temposText(f))
            }
            RunCard {
                VStack(alignment: .leading, spacing: 6) {
                    label("figKeys")
                    Canvas { gc, size in FiguresView.wheel(f, in: &gc, size: size) }
                        .frame(width: RunLook.figureHeight, height: RunLook.figureHeight).frame(maxWidth: .infinity)
                        .rotationEffect(.degrees(watch.moment == "wheel" && !reduce ? 360 : 0))
                        .animation(watch.moment == "wheel" && !reduce ? .easeInOut(duration: RunLook.moment) : nil, value: watch.moment)
                    Text(keysText(f)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                .accessibilityElement(children: .ignore).accessibilityLabel(DeskWords.text("figKeys") + ": " + keysText(f))
            }
            RunCard {
                VStack(alignment: .leading, spacing: 4) {
                    row("figNeedName", f.needName.formatted())
                    row("figSameFile", f.sameFile.formatted())
                    row("figCopies", f.copies.map { $0.formatted() } ?? DeskWords.text("figCopiesLater"))
                    row("figNotIn", f.notIn.formatted())
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func label(_ k: String) -> some View { Text(DeskWords.text(k)).font(.caption.weight(.semibold)).foregroundStyle(.tertiary) }
    private func row(_ k: String, _ v: String) -> some View {
        HStack { Text(DeskWords.text(k)).foregroundStyle(.secondary); Spacer(); Text(v).bold().monospacedDigit() }.font(.callout)
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
        return parts.joined(separator: ", ")
    }

    static func histogram(_ f: RunFigures, latest: Int, in gc: inout GraphicsContext, size: CGSize) {
        let most = max(1, f.tempos.max() ?? 1), slot = size.width / CGFloat(f.tempos.count), barW = max(1, slot - 1)
        gc.fill(Path(CGRect(x: 0, y: size.height - 1, width: size.width, height: 1)), with: .color(Color(nsColor: RunLook.waveNone)))
        for (i, c) in f.tempos.enumerated() where c > 0 {
            let bh = max(2, CGFloat(c) / CGFloat(most) * (size.height - 2))
            gc.fill(Path(CGRect(x: CGFloat(i) * slot, y: size.height - bh, width: barW, height: bh)),
                    with: .color(Color(nsColor: i == latest ? RunLook.waveNew : RunLook.wave)))
        }
    }

    /// The wheel of the twelve home notes round the circle of fifths: the outer ring major, the inner minor, a dot inside
    /// for a song whose home note alone Desk found.
    static let fifths = [0, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10, 5]
    static func wheel(_ f: RunFigures, in gc: inout GraphicsContext, size: CGSize) {
        let s = min(size.width, size.height) / 120, c = CGPoint(x: size.width / 2, y: size.height / 2)
        let most = max(1, max(f.major.max() ?? 0, f.minor.max() ?? 0))
        for (i, pc) in fifths.enumerated() {
            let a0 = Angle.degrees(Double(i) * 30 - 105 + 1.7), a1 = Angle.degrees(Double(i) * 30 - 75 - 1.7)
            for (counts, r0, r1) in [(f.major, 43.0, 58.0), (f.minor, 27.0, 41.0)] {
                var p = Path()
                p.addArc(center: c, radius: r1 * s, startAngle: a0, endAngle: a1, clockwise: false)
                p.addArc(center: c, radius: r0 * s, startAngle: a1, endAngle: a0, clockwise: true)
                p.closeSubpath()
                let n = counts[pc]
                gc.fill(p, with: .color(n > 0 ? RunLook.accent.opacity(0.35 + 0.65 * Double(n) / Double(most)) : RunLook.wheelEmpty))
            }
            if f.home[pc] > 0 {
                let am = (Double(i) * 30 - 90) * .pi / 180, r = min(5, 1.8 + Double(f.home[pc]).squareRoot()) * s
                let at = CGPoint(x: c.x + 18 * s * cos(am), y: c.y + 18 * s * sin(am))
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
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(title).font(.headline)
                    Text(pick.flatMap { watch.songs.indices.contains($0) ? RunWatch.line(watch.songs[$0]) : nil } ?? "")
                        .font(.callout).foregroundStyle(.secondary).lineLimit(1)
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
                .accessibilityLabel(watch.songs.isEmpty ? DeskWords.text("wallEmpty") : title + ", " + Words.songs(watch.songs.count))
                .accessibilityValue(pick.flatMap { watch.songs.indices.contains($0) ? RunWatch.line(watch.songs[$0]) : nil } ?? "")
                Text(DeskWords.text("wallHelp")).font(.caption).foregroundStyle(.tertiary)
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
        let gap = (6 * scale).rounded(), maxCols = max(1, Int((w + gap) / (RunLook.wallColMin * scale + gap)))
        for cols in 1...maxCols {
            let rows = Int((Double(count) / Double(cols)).rounded(.up))
            if h / CGFloat(rows) >= RunLook.wallWaveMin * scale {
                return Plan(wave: true, cols: cols, rows: rows, lh: h / CGFloat(rows), gap: gap, cw: (w - gap * CGFloat(cols - 1)) / CGFloat(cols), scale: scale)
            }
        }
        let dgap = max(1, (2 * scale).rounded())
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
        return (UInt8(s.redComponent * 255), UInt8(s.greenComponent * 255), UInt8(s.blueComponent * 255), Double(s.alphaComponent))
    }

    private static func draw(_ songs: [RunSong], size: CGSize, scale: CGFloat, pick: Int?) -> Made {
        let w = max(1, Int(size.width * scale)), h = max(1, Int(size.height * scale))
        guard !songs.isEmpty, size.width > 0 else { return Made(image: nil, plan: nil, count: 0) }
        let L = plan(songs.count, w: CGFloat(w), h: CGFloat(h), scale: scale)
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let cWave = rgba(RunLook.wave), cQuiet = rgba(RunLook.waveQuiet), cNew = rgba(RunLook.waveNew),
            cPick = rgba(RunLook.wavePick), cNone = rgba(RunLook.waveNone)
        func put(_ x: Int, _ y: Int, _ c: (UInt8, UInt8, UInt8, Double), _ a: Double) {
            let o = (y * w + x) * 4, al = c.3 * a
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
                let v = pow(Double(s.wave[min(n - 1, Int(Double(x - x0) / cw * Double(n)))]) / 99, RunLook.waveCurve)
                if L.wave {
                    let mid = Double(y0 + y1 - 1) / 2, half = max(0.5, v * Double(y1 - y0) * 0.46)
                    var y = max(y0, Int((mid - half).rounded()))
                    while y <= min(y1 - 1, Int((mid + half).rounded())) { put(x, y, c, 1); y += 1 }
                } else {
                    let cc = (c == cWave) ? (v < 0.5 ? cQuiet : cWave) : c
                    for y in y0..<y1 { put(x, y, cc, 0.25 + 0.75 * v) }
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
