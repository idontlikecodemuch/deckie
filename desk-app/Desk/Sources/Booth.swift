import SwiftUI
import DeckieCrate
import DeckieDesk
import DeckieCapture

// The listening mode of the Mac's Desk (research booth-in-desk, step 1: hearing): the same bare mode as the pages'
// (desk-web/booth.js), on the same core: DeckieCapture's Microphone and DeckieDesk's DeskBooth, which builds or opens
// the crate's index and feeds the shared listener. The same words (DeskWords' booth.*), values in Look.swift's
// BoothLook. The song shown is the listener's current named song: not yet the iPad's switching rule (step 2).
//
// The view starts listening when it appears and stops when it goes: leaving the mode, another crate, a run (Desk's
// run screen takes the window, so listening waits and starts again when the run ends), or the window closing.

/// What the mode shows, from DeskBooth's events, on the main thread.
final class BoothModel: ObservableObject, @unchecked Sendable {
    @Published var inputs: [SoundInput] = []
    @Published var chosen: String = ""
    @Published var status: DeskBooth.Status?
    @Published var heard: DeskBooth.Heard?
    @Published var meter: Double = 0
    @Published var clipping = false
    @Published var silent = false
    private var booth: DeskBooth?

    func listInputs() {
        inputs = (try? SoundInputs.list().inputs) ?? []
        if chosen.isEmpty || !inputs.contains(where: { $0.name == chosen }) { chosen = inputs.first?.name ?? "" }
    }

    func start(home: DeskHome, crateId: String, crate: Crate) {
        stop()
        heard = nil; silent = false; meter = 0; status = DeskBooth.Status(state: "starting")
        let source = Microphone(SoundInputs.named(chosen, in: inputs))
        let b = DeskBooth(crate: crate, indexAt: home.shelf.file(DeskBooth.indexFile, of: crateId), source: source) { [weak self] e in
            DispatchQueue.main.async { self?.take(e) }
        }
        booth = b
        b.start()
    }

    func stop() {
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
            if s.state != "listening" && s.state != "nothingHeard" { meter = 0; clipping = false }
        case let .level(l):
            meter = l.meter; clipping = l.clipped > 0; silent = l.silent
        case let .heard(h):
            heard = h
        }
    }

    var hearing: Bool { status?.state == "listening" || status?.state == "nothingHeard" }

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
                    .accessibilityValue("\(Int((booth.meter * 100).rounded()))")
            }
            Text(booth.stateLine(crate: crate))
                .foregroundStyle(booth.status?.state == "error" ? AnyShapeStyle(BoothLook.error) : AnyShapeStyle(.secondary))
            if booth.silent && booth.hearing {
                Text(Words.t("booth.silent")).foregroundStyle(BoothLook.silent)
            }
            if booth.status?.state == "error" {
                Button(Words.t("booth.tryAgain")) { start() }
            }
            BoothSongCard(heard: booth.status?.state == "listening" ? booth.heard : nil)
            Spacer()
        }
        .padding(BoothLook.pad)
        .frame(maxWidth: BoothLook.maxWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { booth.listInputs(); start() }
        .onDisappear { booth.stop() }
        .onChange(of: booth.chosen) { _, _ in start() }
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

private struct BoothSongCard: View {
    let heard: DeskBooth.Heard?
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
