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

/// What the run screen shows, kept as the run goes: the songs, the totals, the song card (the song being worked on,
/// its parts filling in) and the rows of the others worked on at once, the wall, the quiet line, and the moments.
@MainActor
final class RunWatch: ObservableObject {
    /// The card's wave: whose it is, when it came (its sweep in starts then), how long the sweep takes (0: at once),
    /// and its bars to draw.
    struct Staged: Equatable { var song: RunSong; var at: Date; var hold: Double; var draw: Double; var heights: [Double]; var from: [Double] }

    @Published private(set) var songs: [RunSong] = []
    /// The songs on the wall, in the order they went to it (the card's song goes after its moment complete).
    @Published private(set) var wallSongs: [RunSong] = []
    /// The row of the wall lit a moment as a song goes to it.
    @Published private(set) var litRow: Int?
    @Published private(set) var figures = RunFigures()
    @Published private(set) var staged: Staged?
    @Published private(set) var saying = ""
    @Published private(set) var sayingIsMoment = false
    /// The moment showing now, by code, until its motion is over.
    @Published private(set) var moment: String?
    @Published private(set) var momentCount = 0
    /// Bumped at most every `RunLook.wallEvery` when songs joined: the wall redraws on it.
    @Published private(set) var wallVersion = 0
    @Published var visible = true { didSet { if visible && !oldValue { wallVersion += 1 } } }
    /// The song card (the owner's note, Nov 20, 2026): the song being worked on (`RunNow.cardSong`), with what is
    /// worked out of it so far; the song just done, complete a moment (`cardDone`); the other songs worked on (`rows`);
    /// the song read ahead; the stage (a finishing stage shows its words on the card, no song).
    @Published private(set) var card: RunNow?
    @Published private(set) var cardDone: RunSong?
    @Published private(set) var rows: [RunNow] = []
    @Published private(set) var ahead: RunNow?
    @Published private(set) var stage: RunStage = .reading
    private(set) var finishedLine: String?
    private(set) var latestBin = -1
    var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

    private var working: [RunNow] = []
    private var fresh: [RunNote] = []
    private var bags: [String: [String]] = [:]
    private var lastSaid = ""
    private var lastWasFact = false
    private var step: RunStage = .reading
    private var musicCD = false
    private var sayTimer: Timer?, wallTimer: Timer?, doneTimer: Timer?, litTimer: Timer?
    private var spoken = (done: -1, at: Date.distantPast)

    func start(musicCD: Bool) {
        songs = []; wallSongs = []; litRow = nil; figures = RunFigures(); staged = nil; fresh = []; finishedLine = nil
        self.musicCD = musicCD; step = .reading; stage = .reading; lastSaid = ""; saying = ""; moment = nil; latestBin = -1
        spoken = (-1, .distantPast); wallVersion += 1
        working = []; card = nil; cardDone = nil; rows = []; ahead = nil; doneTimer?.invalidate()
        nextSaying()
    }

    /// One progress call of the run.
    func take(_ p: RunProgress) {
        if let s = p.song {
            songs.append(s)
            if let bpm = s.bpm {
                latestBin = max(0, min(p.figures.tempos.count - 1, Int(((bpm - p.figures.tempoLow) / p.figures.tempoStep).rounded(.down))))
            }
            // The card's own song stays complete on the card a moment; any other goes to the wall at once.
            if let c = card, s.rel == c.rel, c.hasParts, cardDone == nil {
                cardDone = s
                doneTimer?.invalidate()
                doneTimer = once(after: RunLook.cardDone) { [weak self] in self?.endDone(); self?.drawCard() }
            } else { toWall(s) }
        }
        figures = p.figures
        for note in p.notes {
            // Lines about one song are not said: the card is the song being worked on (facts about the run are).
            guard note.song == nil else { continue }
            if note.kind == .moment { show(moment: note) } else {
                fresh.removeAll { $0.code == note.code }
                fresh.append(note)
                if fresh.count > 6 { fresh.removeFirst() }
            }
        }
        if p.stage != step { step = p.stage; nextSaying() }
        working = p.stage == .reading ? (!p.working.isEmpty ? p.working : (p.now.map { [$0] } ?? [])) : []
        ahead = p.stage == .reading ? p.ahead : nil
        stage = p.stage
        drawCard()
        speak(p)
    }

    /// The card and the rows from the songs worked on (desk-web/run.js drawCard says the same).
    private func drawCard() {
        if stage != .reading { endDone(); card = nil; rows = []; staged = nil; return }
        if let done = cardDone, let c = card {
            rows = RunNow.rows(working, card: c.rel)
            stageWave(c.rel, done.wave, bpm: done.bpm, bars: done.bars)
            return
        }
        let next = RunNow.cardSong(working, keeping: card?.rel)
        if next != card { card = next }
        rows = RunNow.rows(working, card: next?.rel)
        if let n = next { stageWave(n.rel, n.wave ?? [], bpm: n.bpm, bars: n.bars) } else { staged = nil }
    }

    /// The song done on the card goes to the wall (its row lit a moment), and the card is free for the next.
    private func endDone() {
        doneTimer?.invalidate(); doneTimer = nil
        guard let done = cardDone else { return }
        cardDone = nil; card = nil
        toWall(done)
    }

    private func toWall(_ s: RunSong) {
        wallSongs.append(s)
        litRow = wallSongs.count - 1
        litTimer?.invalidate()
        litTimer = once(after: RunLook.wallNew) { [weak self] in self?.litRow = nil }
        wallSoon()
    }

    /// The card's wave once its loudness is measured: swept in, then moving with the song.
    private func stageWave(_ rel: String, _ wave: [Int], bpm: Double?, bars: Int?) {
        guard !wave.isEmpty else { if staged?.song.id != rel { staged = nil }; return }
        if staged?.song.id == rel, !(staged?.heights.isEmpty ?? true) { return }
        let song = RunSong(id: rel, title: "", artist: nil, bpm: bpm, key: .init(kind: .none), bars: bars, seconds: 0,
                           place: nil, folder: nil, wave: wave, introBars: nil, before: false)
        let still = reduceMotion || !visible
        staged = Staged(song: song, at: Date(), hold: RunLook.hold, draw: still ? 0 : RunLook.draw,
                        heights: RunWatch.bars(song), from: [])
    }

    func stop() {
        for t in [sayTimer, wallTimer, doneTimer, litTimer] { t?.invalidate() }
        if let done = cardDone { cardDone = nil; wallSongs.append(done) }
        // The finished screen's wall has every song of the run.
        wallSongs = songs; litRow = nil
        card = nil; rows = []; ahead = nil; working = []
    }

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
    /// A song's wave as the bars to draw (RunSong.barHeights with the look's values).
    static func bars(_ s: RunSong) -> [Double] {
        RunSong.barHeights(s.wave, bars: s.bars, rangeMin: RunLook.waveRangeMin, floor: RunLook.waveBarFloor)
    }
    static func isQuiet(_ h: Double) -> Bool { h < RunLook.waveBarFloor + (1 - RunLook.waveBarFloor) * RunLook.waveQuietShare }
    /// A song's name on the walls: artist and title.
    static func rowName(_ s: RunSong) -> String {
        s.artist.map { DeskWords.text("wallRowName", ["artist": $0, "title": s.title]) } ?? s.title
    }
    static func whereLine(_ s: RunSong) -> String {
        s.place ?? ((s.folder ?? "").isEmpty ? DeskWords.text("topOfMusicFolder") : s.folder!)
    }
    static func line(_ s: RunSong) -> String {
        Words.wallSong([rowName(s), bpm(s), key(s.key), clock(s.seconds), whereLine(s)])
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

/// The song card (the owner's note, Nov 20, 2026): the song being worked on, by the name Desk has for it, its step line
/// and a thin bar within the song (a turning disc for a music CD's song), and under them its parts filling in as Desk
/// works them out, each in its own place (a quiet placeholder until then): its wave (swept in, then moving with the
/// song), tempo, key, bars, length and where. Done, it stays complete a moment, then goes to the wall. With no song
/// (between songs, before the first, while the crate is finished and saved) it says the step alone. Quietly under it,
/// a disc's next song while it is read ahead. The words are the core's (`RunNow`), as the pages' are.
struct RunSongCard: View {
    @ObservedObject var watch: RunWatch
    let total: Int
    let disc: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce

    var body: some View {
        RunCard {
            VStack(alignment: .leading, spacing: RunLook.songCardGap) {
                head
                HStack(alignment: .center, spacing: RunLook.stageGap) {
                    wave.frame(height: RunLook.stageHeight).frame(maxWidth: .infinity)
                    facts.frame(maxWidth: .infinity, alignment: .leading)
                }
                .opacity(watch.card == nil ? 0 : 1)
                if watch.ahead != nil {
                    Text(RunNow.aheadLine).font(RunLook.nowAheadFont).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
        }
    }

    private var stepWords: String {
        switch watch.stage {
        case .reading: return Words.stageReading
        case .finishing: return Words.stageFinishing
        case .saving: return Words.stageSaving
        }
    }

    private var head: some View {
        HStack(spacing: RunLook.nowGap) {
            if disc {
                TimelineView(.animation(paused: reduce || !watch.visible || watch.card == nil || watch.cardDone != nil)) { context in
                    Image(systemName: RunLook.nowDiscSymbol)
                        .font(RunLook.nowDiscFont).foregroundStyle(.secondary)
                        .rotationEffect(.degrees(reduce ? 0 : context.date.timeIntervalSinceReferenceDate
                            .truncatingRemainder(dividingBy: RunLook.nowDiscTurn) / RunLook.nowDiscTurn * RunLook.wholeTurn))
                }
                .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: RunLook.nowLineGap) {
                if let now = watch.card {
                    HStack(spacing: RunLook.stageNameGap) {
                        Text(now.name).font(RunLook.stageFont).lineLimit(1)
                        if let a = now.artist { Text(a).foregroundStyle(.secondary).lineLimit(1) }
                    }
                    let shown = watch.cardDone != nil ? { var d = now; d.step = "windows"; return d }() : now
                    Text(shown.line(total: total)).font(RunLook.nowFont).lineLimit(1)
                    ProgressView(value: watch.cardDone != nil ? 1 : now.share).tint(RunLook.accent)
                } else {
                    Text(stepWords).font(RunLook.nowFont).lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder private var wave: some View {
        if let s = watch.staged {
            // Moving the whole time it is on the card (letter AD), at most `frame` apart; still under reduced motion
            // and while the window is hidden.
            TimelineView(.animation(minimumInterval: RunLook.frame, paused: reduce || !watch.visible)) { tl in
                Canvas { gc, size in
                    let t0 = CACurrentMediaTime()
                    StageView.draw(s, elapsed: tl.date.timeIntervalSince(s.at), still: reduce, in: &gc, size: size)
                    RunCost.add(from: t0)
                }
            }
            .accessibilityLabel(DeskWords.text("stageWaveLabel", ["title": watch.card?.name ?? ""]))
        } else {
            Canvas { gc, size in
                gc.fill(Path(CGRect(x: 0, y: size.height * (1 - RunLook.stageMarkShare) / 2, width: size.width, height: 1)),
                        with: .color(Color(nsColor: RunLook.waveNone)))
            }
        }
    }

    /// Each part from the song done when it is done, else from the song worked on; nil: not worked out yet.
    private var facts: some View {
        let done = watch.cardDone, now = watch.card
        let bpm = done?.bpm ?? now?.bpm, bars = done?.bars ?? now?.bars, key = done?.key ?? now?.key
        let seconds = done?.seconds ?? now?.seconds
        let place = done.map(RunWatch.whereLine) ?? now.flatMap { n in n.place ?? n.folder.map { $0.isEmpty ? DeskWords.text("topOfMusicFolder") : $0 } }
        let finished = done != nil
        return VStack(alignment: .leading, spacing: RunLook.stageFactsGap) {
            HStack(alignment: .top, spacing: RunLook.stageFactsRowGap) {
                fact("stageTempo", bpm.map { DeskWords.text("bpmValue", ["bpm": String(format: "%.1f", $0)]) } ?? (finished ? DeskWords.text("none") : nil), color: RunLook.amber)
                fact("stageKey", key.map(RunWatch.key) ?? (finished ? DeskWords.text("keyNotSureValue") : nil), color: key?.kind == .key ? .primary : .secondary)
                fact("stageBars", bars.map(String.init) ?? (finished ? DeskWords.text("none") : nil))
                fact("stageLength", seconds.map(RunWatch.clock))
            }
            fact("stageWhere", place)
            if let d = done, d.wave.isEmpty { Text(DeskWords.text("stageNoWave")).font(RunLook.stageNoteFont).foregroundStyle(.tertiary) }
        }
    }

    /// One part in its place: its words, or a quiet placeholder of the same height until it is worked out.
    private func fact(_ label: String, _ value: String?, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: RunLook.stageFactGap) {
            Text(DeskWords.text(label)).font(RunLook.labelFont).foregroundStyle(.tertiary)
            Text(value ?? " ").fontWeight(RunLook.stageValueWeight).monospacedDigit().foregroundStyle(color).lineLimit(1)
                .overlay(alignment: .leading) {
                    if value == nil {
                        Capsule().fill(RunLook.cardPending).frame(width: RunLook.cardPendingWidth, height: RunLook.cardPendingHeight)
                    }
                }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The card's wave, drawn: the bars mirrored about a centre line, swept in, then moving with the song (StageMotion).
@MainActor
enum StageView {

    static func draw(_ st: RunWatch.Staged, elapsed: Double, still: Bool, in gc: inout GraphicsContext, size: CGSize) {
        let s = st.song, w = size.width, markH = (size.height * RunLook.stageMarkShare).rounded(), h = size.height - markH
        guard w > 0, h > 0 else { return }
        let m = StageMotion(bpm: s.bpm, elapsed: elapsed, sweep: st.draw, still: still)
        let edge = CGFloat(m.front) * w
        gc.fill(Path(CGRect(x: 0, y: ((h - RunLook.stageLine) / 2).rounded(), width: w, height: RunLook.stageLine)), with: .color(Color(nsColor: RunLook.waveNone)))
        // The wave: a bar each, mirrored about a centre line, each growing or shrinking from the last song's height to this
        // one's, then breathing with the song (StageMotion); the quiet ones in the quiet tone; the playhead a band of
        // light across them.
        let n = st.heights.count
        if n > 0 {
            let slot = w / CGFloat(n), barW = max(1, slot * (1 - RunLook.waveBarGapShare))
            let playX = m.playhead.map { CGFloat($0) * w }
            for i in 0..<n {
                let base = m.height(i, of: n, from: st.from, to: st.heights)
                let cx = (CGFloat(i) + 0.5) * slot
                let distance = playX.map { Double(abs(cx - $0) / w) }
                let lift = distance.map { m.lift(distance: $0) } ?? 0
                let v = max(RunLook.stageWaveMin, CGFloat(base * m.scale(lift: lift)) * h * RunLook.stageWaveRoom)
                let rect = CGRect(x: cx - barW / 2, y: h / 2 - v / 2, width: barW, height: v)
                gc.fill(Path(rect), with: .color(Color(nsColor: RunWatch.isQuiet(st.heights[i]) ? RunLook.waveQuiet : RunLook.wave)))
                if let d = distance.map({ $0 / RunLook.playheadWidth }), d < 1 {
                    let near = 1 - d    // the playhead's light, brightest at its middle
                    gc.fill(Path(rect), with: .color(RunLook.playheadGlow.opacity(near)))
                }
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

    /// Bar `i` of `n`'s height in a song's bars (another song's bars, sampled to `n`); 0 with none.
    static func shape(_ heights: [Double], _ i: Int, of n: Int) -> Double {
        guard !heights.isEmpty, n > 0 else { return 0 }
        return heights[max(0, min(heights.count - 1, i * heights.count / n))]
    }

    /// Stretch `i`'s height now, on its way from the last song's wave to this one's: each stretch starts in turn from
    /// the left and settles with a small overshoot.
    func height(_ i: Int, of n: Int, from old: [Double], to new: [Double]) -> Double {
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
        f.temposText(songs: Words.songs)
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

/// The crate filling up: a row a song, as they joined, top to bottom, each its wave across the row. The rows scroll in
/// the card (lazily: a crate of thousands makes only the rows in view). Pointing at a row, a click on it, or the arrow
/// keys light it up and say the song's line (its name, tempo, key, length, where) beside the title.
struct WallView: View {
    @ObservedObject var watch: RunWatch
    /// The rows: the songs gone to the wall (reading), or every song of the run (finished).
    var songs: [RunSong]
    var title: String
    @State private var pick: Int?
    @FocusState private var focused: Bool

    var body: some View {
        RunCard(moment: watch.moment == "disc") {
            VStack(alignment: .leading, spacing: RunLook.wallCardGap) {
                // The row pointed at says its song's name in the row itself (WallRow); a screen reader hears the full
                // line from the wall's value below.
                Text(title).font(RunLook.wallTitleFont)
                ScrollViewReader { reader in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: RunLook.wallRowGap) {
                            ForEach(songs.indices, id: \.self) { i in
                                WallRow(song: songs[i], picked: pick == i, newest: i == watch.litRow)
                                    .id(i)
                                    .onHover { inside in if inside { pick = i } else if pick == i && !focused { pick = nil } }
                                    .onTapGesture { focused = true; pick = i }
                            }
                        }
                    }
                    .frame(height: min(RunLook.wallMaxHeight, max(RunLook.wallRowHeight,
                        CGFloat(songs.count) * (RunLook.wallRowHeight + RunLook.wallRowGap))))
                    .onChange(of: songs.count) { _, n in if pick == nil, n > 0 { reader.scrollTo(n - 1, anchor: .bottom) } }
                    .onChange(of: pick) { _, p in if let p { reader.scrollTo(p) } }
                }
                .focusable().focused($focused)
                .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .home, .end]) { press in
                    move(press.key); return .handled
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(songs.isEmpty ? DeskWords.text("wallEmpty") : Words.wallLabel(title, songs: songs.count))
                .accessibilityValue(pick.flatMap { songs.indices.contains($0) ? RunWatch.line(songs[$0]) : nil } ?? "")
                Text(DeskWords.text("wallHelp")).font(RunLook.wallHelpFont).foregroundStyle(.tertiary)
            }
        }
    }

    private func move(_ key: KeyEquivalent) {
        let n = songs.count
        guard n > 0 else { return }
        var i = pick ?? (key == .end ? n - 1 : 0)
        if pick != nil {
            switch key {
            case .downArrow, .rightArrow: i += 1
            case .upArrow, .leftArrow: i -= 1
            case .home: i = 0
            case .end: i = n - 1
            default: break
            }
        }
        pick = max(0, min(n - 1, i))
        if let p = pick { watch.announce(RunWatch.line(songs[p])) }
    }
}

/// One row of a wall: the song's wave as one continuous shape across the row, mirrored about its middle (the owner's
/// note, Nov 20, 2026: no name column); the row pointed at or chosen lit and ringed, its wave faded back and the
/// song's name centred over it (the owner's note, Nov 21, 2026): the name, then its tempo, key and length in the
/// quieter colour when the whole line fits, else the name alone, shortened if it must be.
struct WallRow: View {
    let song: RunSong
    let picked: Bool
    let newest: Bool
    @Environment(\.accessibilityReduceMotion) private var reduce
    var body: some View {
        Canvas { gc, size in WallRow.draw(song, picked: picked, newest: newest, in: &gc, size: size) }
            .opacity(picked ? RunLook.wallPickWaveFade : 1)
            .animation(reduce ? nil : .easeInOut(duration: RunLook.fade), value: picked)
            .frame(height: RunLook.wallRowHeight)
            .background(picked ? RunLook.wallRowPick : RunLook.wallRowFill)
            .overlay { if picked { name.padding(.horizontal, RunLook.wallNamePad) } }
            .overlay(Rectangle().strokeBorder(picked ? RunLook.amber : .clear, lineWidth: RunLook.wallPickRing))
    }

    private var name: some View {
        let title = RunWatch.rowName(song)
        let facts = Words.wallSong(["", RunWatch.bpm(song), RunWatch.key(song.key), RunWatch.clock(song.seconds)])
        return ViewThatFits(in: .horizontal) {
            (Text(title).foregroundColor(.primary) + Text(facts).foregroundColor(.secondary)).fixedSize()
            Text(title).foregroundStyle(.primary).truncationMode(.tail)
        }
        .font(RunLook.wallNameFont).fontWeight(RunLook.wallNameWeight).lineLimit(1)
        .accessibilityHidden(true)
    }

    static func draw(_ s: RunSong, picked: Bool, newest: Bool, in gc: inout GraphicsContext, size: CGSize) {
        let heights = RunWatch.bars(s), pad = RunLook.wallRowPad, room = size.height - 2 * pad
        guard size.width > 0, room > 0 else { return }
        if heights.isEmpty {
            gc.fill(Path(CGRect(x: 0, y: size.height / 2, width: size.width, height: 1)), with: .color(Color(nsColor: RunLook.waveNone)))
            return
        }
        // Each bar from the end of the last to the start of the next: no gaps.
        let n = CGFloat(heights.count)
        for (k, h) in heights.enumerated() {
            let v = max(1, CGFloat(h) * room)
            let x0 = (CGFloat(k) * size.width / n).rounded(), x1 = (CGFloat(k + 1) * size.width / n).rounded()
            let colour: NSColor = picked ? RunLook.wavePick : newest ? RunLook.waveNew : RunWatch.isQuiet(h) ? RunLook.waveQuiet : RunLook.wave
            gc.fill(Path(CGRect(x: x0, y: size.height / 2 - v / 2, width: x1 - x0, height: v)), with: .color(Color(nsColor: colour)))
        }
    }
}
