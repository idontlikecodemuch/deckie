import SwiftUI
import DeckieCrate
import DeckieDesk
import DeckieCapture

// The listening mode of the Mac's Desk (research booth-in-desk, step 1: hearing): the same bare mode as the pages'
// (desk-web/booth.js), on the same core: DeckieCapture's Microphone and DeckieDesk's DeskBooth, which builds or opens
// the crate's index and feeds the shared listener. The same words (DeskWords' booth.*), values in Look.swift's
// BoothLook. The song shown is the iPad's (step 2): DeskBooth runs every reading through the shared switching rule
// (DeckieBooth) and says what it shows as `playing`, with the picks for that song, listed plainly under the card as a
// first look (the designed screen is step 3). When listening stops, the listener's times line is printed and kept
// beside the crate's index (DeskBooth.timesFile).
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
    @Published var picks: DeskBooth.Picks?
    @Published var meter: Double = 0
    @Published var clipping = false
    @Published var silent = false
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
            let listed = (try? SoundInputs.list().inputs) ?? []
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
        heard = nil; playing = nil; picks = nil; silent = false; meter = 0; status = DeskBooth.Status(state: "starting")
        let source = Microphone(SoundInputs.named(chosen, in: inputs))
        let b = DeskBooth(crate: crate, indexAt: home.shelf.file(DeskBooth.indexFile, of: crateId), source: source) { [weak self] e in
            DispatchQueue.main.async { self?.take(e) }
        }
        booth = b
        b.start()
    }

    func stop() {
        asked += 1
        let b = booth
        booth = nil
        b?.stop()
        meter = 0
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
            playing = p
            if p.song == nil { picks = nil }
        case let .picks(p):
            picks = p
        case let .times(line):
            // The Mac's log: standard output (Console, or the terminal Desk was started from); the line is also kept
            // beside the crate's index (DeskBooth.timesFile).
            print("Deckie Desk booth: \(line)")
        }
    }

    /// The states in which the input is on (noSound and nothingNow, added Nov 21, 2026, say themselves in their words).
    static let hearingStates: Set<String> = ["listening", "nothingHeard", "nothingNow", "noSound"]
    var hearing: Bool { status.map { Self.hearingStates.contains($0.state) } ?? false }
    /// The silent line, unless the state line already says no sound is coming.
    var showsSilent: Bool { silent && hearing && status?.state != "noSound" }

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

    var body: some View {
        let crate = model.shownName
        VStack(alignment: .leading, spacing: BoothLook.gap) {
            HStack {
                Text(Words.t("booth.title", ["crate": crate])).font(BoothLook.title)
                Spacer()
                Button(Words.t("booth.leave")) { model.boothOn = false }
            }
            HStack {
                Picker(Words.t("booth.input"), selection: $booth.chosen) {
                    if booth.inputs.isEmpty { Text(Words.t("booth.noInputs")).tag("") }
                    ForEach(booth.inputs, id: \.name) { i in
                        Text(i.isDefault ? Words.t("booth.inputDefault", ["name": i.name]) : i.name).tag(i.name)
                    }
                }
                .frame(maxWidth: BoothLook.inputWidth)
                .disabled(booth.inputs.isEmpty)
                Spacer()
                Meter(value: booth.meter, clipping: booth.clipping)
                    .accessibilityLabel(Words.t("booth.level"))
                    .accessibilityValue(String(Int((booth.meter * 100).rounded())))
            }
            Text(booth.stateLine(crate: crate))
                .foregroundStyle(booth.status?.state == "error" ? AnyShapeStyle(BoothLook.error) : AnyShapeStyle(.secondary))
            if booth.showsSilent {
                Text(Words.t("booth.silent")).foregroundStyle(BoothLook.silent)
            }
            if booth.status?.state == "error" {
                Button(Words.t("booth.tryAgain")) { start() }
            }
            // The song the shared switching rule shows, while the input is on (it stays while nothing is heard for a
            // moment, as on the iPad), with its notes; then its picks.
            let shown = booth.hearing ? booth.playing : nil
            BoothSongCard(heard: shown?.song, note: shown.map(Self.note) ?? "")
            if let s = shown?.song, let p = booth.picks, p.forId == s.id { BoothPicksList(picks: p) }
            Spacer()
        }
        .padding(BoothLook.pad)
        .frame(maxWidth: BoothLook.maxWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { booth.listInputs { changed in if !changed { start() } } }
        .onDisappear { booth.stop() }
        .onChange(of: booth.chosen) { _, _ in start() }
    }

    /// "Not heard just now", "Paused", "Also hearing: ..." (DeskWords' booth.*).
    static func note(_ p: DeskBooth.Playing) -> String {
        var parts: [String] = []
        if p.paused { parts.append(Words.t("booth.paused")) } else if p.notHeard { parts.append(Words.t("booth.notHeard")) }
        if let a = p.alsoHearing { parts.append(Words.t("booth.alsoHearing", ["song": a])) }
        return parts.joined(separator: Words.t("booth.join"))
    }

    private func start() {
        guard let c = model.current, let crate = model.crate else { return }
        booth.start(home: model.home, crateId: c.id, crate: crate)
    }
}

private struct Meter: View {
    let value: Double
    let clipping: Bool
    var body: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(BoothLook.meterTrack)
            Capsule().fill(clipping ? BoothLook.meterClip : BoothLook.meterFill)
                .frame(width: BoothLook.meterWidth * max(0, min(1, value)))
                .animation(.linear(duration: BoothLook.meterTime), value: value)
        }
        .frame(width: BoothLook.meterWidth, height: BoothLook.meterHeight)
    }
}

/// The picks' first look: a heading and a plain list, a line each (name, tempo, key, the move, what is unexpected).
private struct BoothPicksList: View {
    let picks: DeskBooth.Picks
    var body: some View {
        VStack(alignment: .leading, spacing: BoothLook.pickGap) {
            Text(Words.t("booth.picksTitle")).font(BoothLook.picksTitle)
            if picks.picks.isEmpty { Text(Words.t("booth.picksNone")).foregroundStyle(.secondary) }
            ForEach(picks.picks, id: \.id) { p in
                VStack(alignment: .leading, spacing: BoothLook.pickLineGap) {
                    Text([p.title, p.artist].compactMap { $0 }.joined(separator: Words.t("booth.join"))).font(BoothLook.pickTitle)
                    Text(([p.bpmLine, p.key, p.moveLine] + p.tags).filter { !$0.isEmpty }.joined(separator: Words.t("booth.join")))
                        .font(BoothLook.pickFacts).foregroundStyle(.secondary)
                }
                .padding(BoothLook.pickPad)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: BoothLook.pickRadius).fill(BoothLook.card))
                .accessibilityElement(children: .combine)
            }
            if picks.more > 0 { Text(Words.t("booth.picksMore", ["n": "\(picks.more)"])).foregroundStyle(.secondary) }
        }
    }
}

private struct BoothSongCard: View {
    let heard: DeskBooth.Heard?
    var note: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: BoothLook.gap / 3) {
            if let h = heard {
                Text(h.title).font(BoothLook.song)
                if let a = h.artist { Text(a).font(BoothLook.artist).foregroundStyle(.secondary) }
                HStack(spacing: BoothLook.factGap) {
                    if let b = h.bpm { Text(Words.t("booth.tempo", ["bpm": "\(Int(b.rounded()))"])) }
                    if let k = h.camelot { Text(Words.t("booth.key", ["camelot": k])) }
                    Text(Words.t("booth.place", ["place": Self.mmss(h.place), "length": Self.mmss(h.seconds)]))
                }
                .font(BoothLook.facts)
                if !note.isEmpty { Text(note).font(BoothLook.note).foregroundStyle(.secondary) }
            }
        }
        .padding(BoothLook.cardPad)
        .frame(maxWidth: .infinity, minHeight: BoothLook.cardMinHeight, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: BoothLook.cardRadius).fill(BoothLook.card))
        .opacity(heard == nil ? BoothLook.emptyOpacity : 1)
        .accessibilityElement(children: .combine)
    }
    static func mmss(_ s: Double) -> String { let t = Int(max(0, s)); return String(format: "%d:%02d", t / 60, t % 60) }
}
