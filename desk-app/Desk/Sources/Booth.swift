import SwiftUI
import DeckieCrate
import DeckieDesk
import DeckieCapture

// Booth, the listening mode of the Mac's Desk (research booth-in-desk; the designed screen, step 3, D44): the same
// screen as the pages' (desk-web/booth.js), on the same core: DeckieCapture's Microphone and DeckieDesk's DeskBooth,
// which builds or opens the crate's index, feeds the shared listener, runs each reading through the shared switching
// rule and says the song shown and its picks (the iPad's). The same words (DeskWords' booth.*, and the shared pick.*),
// values in Look.swift's BoothLook. While Booth shows, the window takes Booth's ground, the toolbar included
// (ContentView), so listening is never taken for the crate side.
//
// The screen: the head (Booth, whether it is listening, the crate, Back to songs); the song playing, big, with its
// tempo, key, pitch and its place along its wave; its picks as rows with the Shuffle dial, which rolls them again at
// once (DeskBooth.setShuffle), and the iPad's More; at the foot the input, its level, Stop listening and the microphone
// sentence. When listening stops, the listener's times line is printed and kept beside the crate's index.
//
// The view starts listening when it appears and stops when it goes: leaving the mode, another crate, a run (Desk's
// run screen takes the window, so listening waits and starts again when the run ends), or the window closing.

/// What the mode shows, from DeskBooth's events, on the main thread.
final class BoothModel: ObservableObject, @unchecked Sendable {
    @Published var inputs: [SoundInput] = []
    @Published var chosen: String = ""
    @Published var status: DeskBooth.Status?
    @Published var heard: DeskBooth.Heard?
    @Published var playing: DeskBooth.Playing?
    @Published var playingAt = Date()
    @Published var picks: DeskBooth.Picks?
    @Published var meter: Double = 0
    @Published var clipping = false
    @Published var silent = false
    /// The DJ pressed Stop listening: the microphone is off; the song stays, dimmed, with its picks.
    @Published var stopped = false
    @Published var shuffle = BoothLook.shuffleStart
    /// Songs the crate's index can name.
    @Published var songs: Int?
    private var booth: DeskBooth?

    /// Counts each listing asked for and each stop, so a listing that answers after the mode was left starts nothing.
    private var asked = 0

    /// Lists the inputs off the main thread (the system's sound may take up to `SoundInputs.answerWithin` seconds to
    /// answer, and the window must not stop meanwhile; the mode says "starting"), then `then` on the main thread, unless
    /// the mode was left meanwhile. `then` is told whether the chosen input changed (its own change starts listening).
    func listInputs(then: @escaping @MainActor @Sendable (_ chosenChanged: Bool) -> Void) {
        asked += 1
        let ask = asked
        status = DeskBooth.Status(state: "starting")
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // The engine's stand-in for an input (DECKIE_BOOTH_SOUND, pictures with no microphone): listed alone, as on the pages.
            let standIn = Self.standIn.map { [SoundInput(name: URL(fileURLWithPath: $0).lastPathComponent, isDefault: true)] }
            let listed = standIn ?? (try? SoundInputs.list().inputs) ?? []
            DispatchQueue.main.async {
                guard let self, self.asked == ask else { return }
                self.inputs = listed
                let was = self.chosen
                if self.chosen.isEmpty || !listed.contains(where: { $0.name == self.chosen }) { self.chosen = listed.first?.name ?? "" }
                then(self.chosen != was)
            }
        }
    }

    func start(home: DeskHome, crateId: String, crate: Crate) {
        stop()
        stopped = false
        heard = nil; playing = nil; picks = nil; silent = false; meter = 0; status = DeskBooth.Status(state: "starting")
        let source: SoundSource = Self.standIn.flatMap { try? DeskProtocol.standInSource($0) }
            ?? Microphone(SoundInputs.named(chosen, in: inputs))
        let b = DeskBooth(crate: crate, indexAt: home.shelf.file(DeskBooth.indexFile, of: crateId), source: source, shuffle: shuffle) { [weak self] e in
            DispatchQueue.main.async { self?.take(e) }
        }
        booth = b
        songs = b.songCount
        b.start()
    }

    /// The file `DECKIE_BOOTH_SOUND` names, played as if the microphone heard it (checks and pictures; never set by Desk).
    static var standIn: String? { ProcessInfo.processInfo.environment[DeskProtocol.soundStandIn] }

    func stop() {
        asked += 1
        let b = booth
        booth = nil
        b?.stop()
        meter = 0
    }

    /// Stop listening, staying in the mode.
    func stopListening() {
        stop()
        stopped = true
        status = DeskBooth.Status(state: "stopped")
    }

    /// The dial let go: the picks are rolled again with it, at once (the iPad's).
    func moveDial() {
        booth?.setShuffle(shuffle)
    }

    private func take(_ e: DeskBooth.Event) {
        guard booth != nil else { return }
        switch e {
        case let .status(s):
            status = s
            if s.state != "listening" { heard = nil }
            if !Self.hearingStates.contains(s.state) { meter = 0; clipping = false }
        case let .level(l):
            meter = l.meter; clipping = l.clipped > 0; silent = l.silent
        case let .heard(h):
            heard = h
        case let .playing(p):
            playing = p; playingAt = Date()
            if p.song == nil { picks = nil }
        case let .picks(p):
            picks = p
            shuffle = p.shuffle
        case let .times(line):
            // The Mac's log: standard output (Console, or the terminal Desk was started from); the line is also kept
            // beside the crate's index (DeskBooth.timesFile).
            print("Deckie Desk booth: \(line)")
        }
    }

    /// The states in which the input is on (noSound and nothingNow, added Nov 21, 2026, say themselves in their words).
    static let hearingStates: Set<String> = ["listening", "nothingHeard", "nothingNow", "noSound"]
    var hearing: Bool { !stopped && (status.map { Self.hearingStates.contains($0.state) } ?? false) }

    /// The song on the card: the shared rule's while the input is on, and kept after Stop listening.
    var shown: DeskBooth.Playing? { (hearing || stopped) && playing?.song != nil ? playing : nil }

    /// Where in the song it is at `date`: the rule's place moved on at its rate (still while paused, not heard or stopped).
    func place(at date: Date) -> Double {
        guard let p = playing, let s = p.song else { return 0 }
        var at = max(0, s.place)
        if !stopped && !p.paused && !p.notHeard { at += date.timeIntervalSince(playingAt) * (p.rate > 0 ? p.rate : 1) }
        return s.seconds > 0 ? min(s.seconds, at) : at
    }

    /// The state line, in DeskWords' booth.* words.
    func stateLine(crate: String) -> String {
        guard let s = status else { return Words.t("booth.state.starting") }
        switch s.state {
        case "index": return Words.t("booth.state.index", ["crate": crate, "percent": "\(s.percent ?? 0)"])
        case "error":
            let code = s.error?.code ?? "other"
            return Words.t(DeskWords.table["booth.error.\(code)"] != nil ? "booth.error.\(code)" : "booth.error.other")
        default: return Words.t("booth.state.\(s.state)", ["crate": crate])
        }
    }
}

struct BoothView: View {
    @EnvironmentObject var model: DeskModel
    @ObservedObject var booth: BoothModel
    private let g = BoothLook.ground

    private var songsHere: Bool { !(model.crate?.tracks.isEmpty ?? true) }

    var body: some View {
        let crate = model.shownName
        VStack(alignment: .leading, spacing: BoothLook.gap) {
            head(crate)
            HStack(alignment: .top, spacing: BoothLook.columnGap) {
                BoothNowCard(booth: booth, crate: crate, songsHere: songsHere, start: start)
                    .frame(maxWidth: .infinity, alignment: .top)
                BoothPicksColumn(booth: booth, crate: crate)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .frame(maxHeight: .infinity, alignment: .top)
            foot(crate)
        }
        .padding(.horizontal, BoothLook.pad).padding(.top, BoothLook.padTop).padding(.bottom, BoothLook.padTop)
        .frame(maxWidth: BoothLook.maxWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(BoothLook.text)
        .background(g.background.ignoresSafeArea())
        .environment(\.colorScheme, .dark)
        .onAppear { if songsHere { booth.listInputs { changed in if !changed { start() } } } }
        .onDisappear { booth.stop() }
        .onChange(of: booth.chosen) { _, _ in if !booth.stopped { start() } }
    }

    private func head(_ crate: String) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: BoothLook.headingGap) {
                HStack(spacing: BoothLook.headGap) {
                    Text(Words.t("booth.heading")).font(BoothLook.heading)
                    let getting = ["starting", "index"].contains(booth.status?.state ?? "") && !booth.stopped
                    HStack(spacing: BoothLook.liveGap) {
                        Circle().fill(booth.hearing ? g.live : g.dim).frame(width: BoothLook.liveDot, height: BoothLook.liveDot)
                        Text(Words.t(booth.hearing ? "booth.state.listening" : getting ? "booth.state.starting" : "booth.state.stopped"))
                            .font(BoothLook.liveFont).foregroundStyle(booth.hearing ? BoothLook.text : g.mut)
                    }
                    .padding(.horizontal, BoothLook.livePadH).padding(.vertical, BoothLook.livePadV)
                    .background(Capsule().fill(BoothLook.liveFill))
                    .accessibilityElement(children: .combine)
                }
                Text(Words.t("booth.title", ["crate": crate])).font(BoothLook.sub).foregroundStyle(g.mut)
            }
            Spacer()
            Button(Words.t("booth.leave")) { model.boothOn = false }.font(BoothLook.leaveFont).controlSize(.large)
        }
    }

    private func foot(_ crate: String) -> some View {
        VStack(alignment: .leading, spacing: BoothLook.headingGap) {
            Rectangle().fill(g.line).frame(height: BoothLook.cardLine)
            if let line = inputNote(crate) { Text(line).foregroundStyle(BoothLook.warn) }
            HStack(spacing: BoothLook.footGap) {
                Picker(Words.t("booth.input"), selection: $booth.chosen) {
                    if booth.inputs.isEmpty { Text(Words.t("booth.noInputs")).tag("") }
                    ForEach(booth.inputs, id: \.name) { i in
                        Text(i.isDefault ? Words.t("booth.inputDefault", ["name": i.name]) : i.name).tag(i.name)
                    }
                }
                .frame(maxWidth: BoothLook.inputWidth)
                .disabled(booth.inputs.isEmpty || !songsHere)
                BoothMeter(value: booth.hearing ? booth.meter : 0, clipping: booth.clipping)
                    .accessibilityLabel(Words.t("booth.level"))
                    .accessibilityValue(String(Int((booth.meter * 100).rounded())))
                if songsHere && !booth.stopped && !["error", "stopped"].contains(booth.status?.state ?? "") {
                    Button(Words.t("booth.stopListening")) { booth.stopListening() }
                }
                Text(Words.t("booth.micPermission")).font(BoothLook.privacy).foregroundStyle(g.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, BoothLook.headingGap)
        }
    }

    /// The foot's line about the input, while a song is on the card (with no song the card says it).
    private func inputNote(_ crate: String) -> String? {
        guard booth.hearing, booth.shown != nil else { return nil }
        if booth.status?.state == "noSound" { return booth.stateLine(crate: crate) }
        return booth.silent ? Words.t("booth.silent") : nil
    }

    private func start() {
        guard let c = model.current, let crate = model.crate else { return }
        booth.start(home: model.home, crateId: c.id, crate: crate)
    }
}

/// The song playing, big; before a song, what Booth is doing in its place.
private struct BoothNowCard: View {
    @ObservedObject var booth: BoothModel
    let crate: String
    let songsHere: Bool
    let start: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let g = BoothLook.ground

    var body: some View {
        let shown = booth.shown
        VStack(alignment: .leading, spacing: BoothLook.cardGap) {
            Text(Words.t("booth.nowPlaying").uppercased()).font(BoothLook.group).kerning(BoothLook.groupKerning).foregroundStyle(g.dim)
            if let p = shown, let s = p.song {
                song(p, s).id(s.id)
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: BoothLook.rise)))
            } else {
                Spacer(minLength: 0)
                waiting
                Spacer(minLength: 0)
            }
        }
        .padding(BoothLook.cardPad)
        .frame(maxWidth: .infinity, minHeight: BoothLook.cardMinHeight, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: BoothLook.cardRadius).fill(g.card))
        .overlay(RoundedRectangle(cornerRadius: BoothLook.cardRadius).stroke(g.cardEdge, lineWidth: BoothLook.cardLine))
        .background(glow)
        .animation(reduceMotion ? nil : .easeOut(duration: BoothLook.arrive), value: shown?.song?.id)
    }

    /// A soft glow behind the card that follows the level while listening (still under reduced motion).
    private var glow: some View {
        RoundedRectangle(cornerRadius: BoothLook.cardRadius).fill(g.glow)
            .padding(-BoothLook.glowSpread).blur(radius: BoothLook.glowBlur)
            .opacity(booth.hearing ? BoothLook.glowFloor + (reduceMotion ? 0 : booth.meter) * BoothLook.glowRange : 0)
            .allowsHitTesting(false)
    }

    private func song(_ p: DeskBooth.Playing, _ s: DeskBooth.Heard) -> some View {
        let quiet = booth.stopped || p.paused || p.notHeard
        return VStack(alignment: .leading, spacing: BoothLook.cardGap) {
            VStack(alignment: .leading, spacing: BoothLook.cardGap) {
                Text(s.title).font(BoothLook.song).lineLimit(BoothLook.songLines)
                if let a = s.artist { Text(a).font(BoothLook.artist).foregroundStyle(g.mut) }
                HStack(alignment: .firstTextBaseline, spacing: BoothLook.factGap) {
                    if let b = s.bpm { Text(Words.t("booth.tempo", ["bpm": "\(Int((b * (p.rate > 0 ? p.rate : 1)).rounded()))"])).font(BoothLook.tempoFont).foregroundStyle(BoothLook.tempo) }
                    if let k = s.camelot { Text(Words.t("booth.key", ["camelot": k])).font(BoothLook.keyFont) }
                    if abs(p.pitch) >= BoothLook.pitchShown { Text(Words.t("booth.pitch", ["pitch": Self.signed(p.pitch)])).font(BoothLook.pitchFont).foregroundStyle(g.mut) }
                }
            }
            .opacity(quiet ? BoothLook.quietOpacity : 1)
            if let n = note(p) { Text(n).font(BoothLook.note).foregroundStyle(g.mut) }
            TimelineView(.periodic(from: .now, by: BoothLook.tick)) { ctx in
                let at = booth.place(at: ctx.date)
                VStack(alignment: .leading, spacing: BoothLook.cardGap) {
                    BoothWave(wave: s.wave ?? [], bars: s.bars, share: s.seconds > 0 ? at / s.seconds : 0)
                        .frame(height: BoothLook.waveHeight).opacity(quiet ? BoothLook.quietOpacity : 1)
                    HStack {
                        Text(Words.t("booth.place", ["place": Self.mmss(at), "length": Self.mmss(s.seconds)]))
                        Spacer()
                        if s.seconds > 0 { Text(Words.t("booth.left", ["time": Self.mmss(s.seconds - at)])) }
                    }
                    .font(BoothLook.times).foregroundStyle(g.mut)
                }
            }
            if booth.stopped { Button(Words.t("booth.startListening")) { start() }.buttonStyle(.borderedProminent).tint(g.on) }
        }
        .accessibilityElement(children: .contain)
    }

    /// "Not listening", "Paused", "Not heard just now", "Also hearing: ..." (DeskWords' booth.*).
    private func note(_ p: DeskBooth.Playing) -> String? {
        var parts: [String] = []
        if booth.stopped { parts.append(Words.t("booth.state.stopped")) }
        else {
            if p.paused { parts.append(Words.t("booth.paused")) } else if p.notHeard { parts.append(Words.t("booth.notHeard")) }
            if let a = p.alsoHearing { parts.append(Words.t("booth.alsoHearing", ["song": a])) }
        }
        return parts.isEmpty ? nil : parts.joined(separator: Words.t("booth.join"))
    }

    /// The card with no song: a big line and the plain one under it, in the words the tables have.
    private var waiting: some View {
        let state = booth.status?.state
        var big = Words.t("booth.waitingTitle"), line: String? = booth.stateLine(crate: crate), warn = false
        if !songsHere { big = Words.t("booth.heading"); line = Words.t("booth.emptyCrate", ["crate": crate]) }
        else if booth.stopped { big = Words.t("booth.state.stopped"); line = Words.t("booth.stoppedHelp") }
        else if state == nil || state == "starting" { big = Words.t("booth.state.starting"); line = nil }
        else if state == "index" { big = Words.t("booth.state.starting") }
        else if state == "error" { big = Words.t("booth.state.stopped"); warn = true }
        else if state == "noSound" { warn = true }
        else if state == "listening" { line = Words.t("booth.waitingHelp") }
        return VStack(alignment: .leading, spacing: BoothLook.cardGap) {
            Text(big).font(BoothLook.waitFont)
            if let line { Text(line).font(BoothLook.stateFont).foregroundStyle(warn ? BoothLook.warn : g.mut).fixedSize(horizontal: false, vertical: true) }
            if state == "index" { ProgressView(value: Double(booth.status?.percent ?? 0), total: 100).tint(g.on) }
            if songsHere && (booth.stopped || state == "error") {
                Button(Words.t(booth.stopped ? "booth.startListening" : "booth.tryAgain")) { start() }.buttonStyle(.borderedProminent).tint(g.on)
            }
        }
        .frame(maxWidth: BoothLook.waitWidth, alignment: .leading)
    }

    static func mmss(_ s: Double) -> String { let t = Int(max(0, s)); return String(format: "%d:%02d", t / 60, t % 60) }
    static func signed(_ p: Double) -> String {
        Words.t("pick.signed", ["sign": Words.t(p > 0.05 ? "pick.sign.plus" : p < -0.05 ? "pick.sign.minus" : "pick.sign.none"),
                                "value": String(format: "%.1f", abs(p))])
    }
}

/// The song's wave (RunSong.barHeights, as the reading screen draws it), the part played lit, a line where the song is;
/// a thin line for a song with no wave.
private struct BoothWave: View {
    let wave: [Int]
    let bars: Int?
    let share: Double
    private let g = BoothLook.ground

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height, mid = h / 2
            let heights = RunSong.barHeights(wave, bars: bars, rangeMin: RunLook.waveRangeMin, floor: RunLook.waveBarFloor)
            if heights.isEmpty { ctx.fill(Path(CGRect(x: 0, y: mid, width: w, height: BoothLook.flatLine)), with: .color(g.waveQuiet)) }
            let slot = w / CGFloat(max(1, heights.count))
            for (k, v) in heights.enumerated() {
                let bh = max(BoothLook.flatLine, CGFloat(v) * h * BoothLook.waveRoom)
                let played = (Double(k) + 0.5) / Double(heights.count) <= share
                let quietBar = v < RunLook.waveBarFloor + (1 - RunLook.waveBarFloor) * RunLook.waveQuietShare
                let colour = played ? g.wavePlayed : quietBar ? g.waveQuiet : g.waveAhead
                ctx.fill(Path(CGRect(x: CGFloat(k) * slot, y: mid - bh / 2, width: max(BoothLook.flatLine, slot * (1 - BoothLook.waveGapShare)), height: bh)), with: .color(colour))
            }
            let x = min(w - BoothLook.playheadWidth, max(0, CGFloat(share) * w - BoothLook.playheadWidth / 2))
            ctx.fill(Path(CGRect(x: x, y: 0, width: BoothLook.playheadWidth, height: h)), with: .color(g.playhead))
        }
        .accessibilityHidden(true)
    }
}

/// The picks: the group, the Shuffle dial, the rows; More; how many more; a line for a crate with few songs.
private struct BoothPicksColumn: View {
    @ObservedObject var booth: BoothModel
    let crate: String
    @State private var dragging = false
    private let g = BoothLook.ground

    var body: some View {
        let shown = booth.shown
        let picks = shown.flatMap { s in booth.picks.flatMap { $0.forId == s.song?.id ? $0 : nil } }
        VStack(alignment: .leading, spacing: BoothLook.listGap) {
            HStack {
                Text(Words.t("booth.picksTitle").uppercased()).font(BoothLook.group).kerning(BoothLook.groupKerning).foregroundStyle(g.dim)
                Spacer()
                HStack(spacing: BoothLook.dialGap) {
                    Text(Words.t("booth.shuffle")).foregroundStyle(g.dim)
                    Text(Words.t("booth.percent", ["n": "\(Int((booth.shuffle * 100).rounded()))"])).frame(width: BoothLook.dialValueWidth, alignment: .leading)
                    Slider(value: $booth.shuffle, in: 0...1, step: BoothLook.shuffleStep) { editing in
                        dragging = editing
                        if !editing { booth.moveDial() }
                    }
                    .frame(width: BoothLook.dialWidth).tint(g.on)
                    .accessibilityLabel(Words.t("booth.shuffle"))
                }
                .font(BoothLook.dialFont)
                .help(Words.t("booth.shuffleHelp"))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: BoothLook.listGap) {
                    if let p = picks {
                        if p.picks.isEmpty { Text(Words.t("booth.picksNone")).font(BoothLook.quiet).foregroundStyle(g.mut) }
                        ForEach(p.picks, id: \.id) { k in BoothPickRow(pick: k, small: false) }
                        if !p.morePicks.isEmpty {
                            Text(Words.t("booth.moreTitle").uppercased()).font(BoothLook.group).kerning(BoothLook.groupKerning).foregroundStyle(g.dim)
                                .padding(.top, BoothLook.moreAbove)
                            ForEach(p.morePicks, id: \.id) { k in BoothPickRow(pick: k, small: true) }
                        }
                        let rest = max(0, p.more - p.morePicks.count)
                        if rest > 0 { Text(Words.t("booth.picksMore", ["n": "\(rest)"])).font(BoothLook.quiet).foregroundStyle(g.mut) }
                    } else {
                        Text(Words.t("booth.picksWait")).font(BoothLook.quiet).foregroundStyle(g.mut)
                    }
                    if let n = booth.songs, n > 0, n < BoothLook.fewSongs {
                        Text(Words.t("booth.fewSongs", ["crate": crate, "n": "\(n)"])).font(BoothLook.quiet).foregroundStyle(g.mut)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .animation(.easeOut(duration: BoothLook.pickFade), value: picks.map { $0.picks.map(\.id) + ["\($0.shuffle)"] })
            }
        }
    }
}

/// One pick as a row: its name and artist, the tempo line and the move; the keys and what is unexpected at its side.
private struct BoothPickRow: View {
    let pick: DeskBooth.Pick
    let small: Bool
    private let g = BoothLook.ground

    var body: some View {
        HStack(alignment: .top, spacing: BoothLook.pickGap) {
            VStack(alignment: .leading, spacing: BoothLook.pickLines) {
                Text(pick.title).font(small ? BoothLook.pickTitleSmall : BoothLook.pickTitle).lineLimit(1)
                if let a = pick.artist { Text(a).foregroundStyle(g.mut).lineLimit(1) }
                HStack(spacing: BoothLook.lineGap) {
                    Text(pick.bpmLine).foregroundStyle(BoothLook.tempo)
                    if !pick.moveLine.isEmpty { Text(pick.moveLine).foregroundStyle(pick.keysClash ? BoothLook.clash : g.mut) }
                }
                .font(BoothLook.pickLine).lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: BoothLook.tagGap) {
                Text(pick.keys.isEmpty ? pick.key : pick.keys).font(BoothLook.pickKeys)
                HStack(spacing: BoothLook.tagGap) {
                    ForEach(pick.tags, id: \.self) { t in
                        Text(t).font(BoothLook.tagFont).foregroundStyle(g.mut)
                            .padding(.horizontal, BoothLook.tagPadH).padding(.vertical, BoothLook.tagPadV)
                            .background(Capsule().fill(g.surface))
                    }
                }
            }
        }
        .padding(.horizontal, BoothLook.pickPadH).padding(.vertical, BoothLook.pickPadV)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: BoothLook.pickRadius).fill(g.surface))
        .accessibilityElement(children: .combine)
    }
}

private struct BoothMeter: View {
    let value: Double
    let clipping: Bool
    private let g = BoothLook.ground
    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(BoothLook.meterTrack)
            Capsule().fill(clipping ? BoothLook.meterClip : g.on)
                .frame(width: BoothLook.meterWidth * max(0, min(1, value)))
        }
        .frame(width: BoothLook.meterWidth, height: BoothLook.meterHeight)
    }
}
